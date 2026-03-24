/*
 * Avalon memory-mapped peripheral that generates VGA
 *
 * Stephen A. Edwards
 * Columbia University
 *
 * Register map:
 *
 * Byte Offset  31 ... 0   Meaning
 *        0    |    X    |  Horizontal center of the ball in pixels (0-639)
 *        4    |    Y    |  Vertical center of the ball in pixels (0-479)
 */

module vga_ball(input logic        clk,
	        input logic 	   reset,
		input logic [31:0] writedata,
		input logic 	   write,
		input logic 	   chipselect,
		input logic [0:0]  address,

		output logic [7:0] VGA_R, VGA_G, VGA_B,
		output logic 	   VGA_CLK, VGA_HS, VGA_VS,
		                   VGA_BLANK_n,
		output logic 	   VGA_SYNC_n);

   logic [10:0]	   hcount;
   logic [9:0]     vcount;

   localparam logic [9:0] DEFAULT_BALL_X = 10'd320;
   localparam logic [9:0] DEFAULT_BALL_Y = 10'd240;
   localparam logic [9:0] BALL_RADIUS = 10'd8;

   logic [9:0]      pending_ball_x, pending_ball_y;
   logic [9:0]      ball_x, ball_y;
   logic signed [11:0] dx, dy;
   logic [23:0]     distance_sq;
   logic [23:0]     radius_sq;
   logic            draw_ball;
	
   vga_counters counters(.clk50(clk), .*);

   always_ff @(posedge clk)
     if (reset) begin
	pending_ball_x <= DEFAULT_BALL_X;
	pending_ball_y <= DEFAULT_BALL_Y;
	ball_x <= DEFAULT_BALL_X;
	ball_y <= DEFAULT_BALL_Y;
     end else begin
       if (chipselect && write)
	 case (address)
	   1'b0 : pending_ball_x <= (writedata[9:0] > 10'd639) ?
				   10'd639 : writedata[9:0];
	   1'b1 : pending_ball_y <= (writedata[9:0] > 10'd479) ?
				   10'd479 : writedata[9:0];
	 endcase

       // Latch a new ball position only at the start of vertical blanking
       // to avoid tearing from mid-frame coordinate changes.
       if (hcount == 11'd0 && vcount == 10'd480) begin
	  ball_x <= pending_ball_x;
	  ball_y <= pending_ball_y;
       end
     end

   assign dx = $signed({1'b0, hcount[10:1]}) - $signed({1'b0, ball_x});
   assign dy = $signed({1'b0, vcount}) - $signed({1'b0, ball_y});
   assign distance_sq = dx * dx + dy * dy;
   assign radius_sq = BALL_RADIUS * BALL_RADIUS;
   assign draw_ball = distance_sq <= radius_sq;

   always_comb begin
      {VGA_R, VGA_G, VGA_B} = {8'h0, 8'h0, 8'h0};
      if (VGA_BLANK_n )
	if (draw_ball)
	  {VGA_R, VGA_G, VGA_B} = {8'hff, 8'hff, 8'hff};
	else
	  {VGA_R, VGA_G, VGA_B} =
             {8'h20, 8'h20, 8'h80};
   end
	       
endmodule

module vga_counters(
 input logic 	     clk50, reset,
 output logic [10:0] hcount,  // hcount[10:1] is pixel column
 output logic [9:0]  vcount,  // vcount[9:0] is pixel row
 output logic 	     VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_n, VGA_SYNC_n);

/*
 * 640 X 480 VGA timing for a 50 MHz clock: one pixel every other cycle
 * 
 * HCOUNT 1599 0             1279       1599 0
 *             _______________              ________
 * ___________|    Video      |____________|  Video
 * 
 * 
 * |SYNC| BP |<-- HACTIVE -->|FP|SYNC| BP |<-- HACTIVE
 *       _______________________      _____________
 * |____|       VGA_HS          |____|
 */
   // Parameters for hcount
   parameter HACTIVE      = 11'd 1280,
             HFRONT_PORCH = 11'd 32,
             HSYNC        = 11'd 192,
             HBACK_PORCH  = 11'd 96,   
             HTOTAL       = HACTIVE + HFRONT_PORCH + HSYNC +
                            HBACK_PORCH; // 1600
   
   // Parameters for vcount
   parameter VACTIVE      = 10'd 480,
             VFRONT_PORCH = 10'd 10,
             VSYNC        = 10'd 2,
             VBACK_PORCH  = 10'd 33,
             VTOTAL       = VACTIVE + VFRONT_PORCH + VSYNC +
                            VBACK_PORCH; // 525

   logic endOfLine;
   
   always_ff @(posedge clk50 or posedge reset)
     if (reset)          hcount <= 0;
     else if (endOfLine) hcount <= 0;
     else  	         hcount <= hcount + 11'd 1;

   assign endOfLine = hcount == HTOTAL - 1;
       
   logic endOfField;
   
   always_ff @(posedge clk50 or posedge reset)
     if (reset)          vcount <= 0;
     else if (endOfLine)
       if (endOfField)   vcount <= 0;
       else              vcount <= vcount + 10'd 1;

   assign endOfField = vcount == VTOTAL - 1;

   // Horizontal sync: from 0x520 to 0x5DF (0x57F)
   // 101 0010 0000 to 101 1101 1111
   assign VGA_HS = !( (hcount[10:8] == 3'b101) &
		      !(hcount[7:5] == 3'b111));
   assign VGA_VS = !( vcount[9:1] == (VACTIVE + VFRONT_PORCH) / 2);

   assign VGA_SYNC_n = 1'b0; // For putting sync on the green signal; unused
   
   // Horizontal active: 0 to 1279     Vertical active: 0 to 479
   // 101 0000 0000  1280	       01 1110 0000  480
   // 110 0011 1111  1599	       10 0000 1100  524
   assign VGA_BLANK_n = !( hcount[10] & (hcount[9] | hcount[8]) ) &
			!( vcount[9] | (vcount[8:5] == 4'b1111) );

   /* VGA_CLK is 25 MHz
    *             __    __    __
    * clk50    __|  |__|  |__|
    *        
    *             _____       __
    * hcount[0]__|     |_____|
    */
   assign VGA_CLK = hcount[0]; // 25 MHz clock: rising edge sensitive
   
endmodule

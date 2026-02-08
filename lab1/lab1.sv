// CSEE 4840 Lab 1: Run and Display Collatz Conjecture Iteration Counts
//
// Spring 2023
//
// By: <your name here>
// Uni: <your uni here>

module lab1( input logic CLOCK_50,  // 50 MHz Clock input
	     input logic [3:0] 	KEY, // Pushbuttons; KEY[0] is rightmost
	     input logic [9:0] 	SW, // Switches; SW[0] is rightmost
	     // 7-segment LED displays; HEX0 is rightmost
	     output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
	     output logic [9:0] LEDR // LEDs above the switches; LED[0] on right
	     );

      logic clk, go, done;   
      logic [31:0] start;
      logic [15:0] count;

      logic [11:0] n;
      
      assign clk = CLOCK_50;
      
      range #(256, 8) // RAM_WORDS = 256, RAM_ADDR_BITS = 8)
            r ( .* ); // Connect everything with matching names

      // Replace this comment and the code below it with your own code;
      // The code below is merely to suppress Verilator lint warnings
      logic [31:0] base_n = 32'd0;
      logic [7:0] offset;
      logic done_seen;
      logic [15:0] count_reg;
      logic [3:0] key_pressed, key_pressed_d; //KEY on DE1-SoC is active-low ---- pressed == 0

      logic [22:0] hold_cnt;
      logic tick;


      logic go_reg; //one cycle pulse

      logic [31:0] cur_n; //display part
      logic [11:0] n12;
      logic [11:0] c12;

      assign key_pressed = ~KEY; //negate pressed when button down
      assign go = go_reg;
      


      //use start as RAM address
      always_comb begin
            assign start = done_seen ? {24'b0, offset} : base_n;
      end


      //computer displayed n
      assign cur_n = base_n + {24'b0, offset};
      assign n12 = cur_n[11:0];
      assign c12 = cur_n[11:0];

      always_comb begin
            LEDR = SW;
            LEDR[9] = done_seen;// 1 when results ready
            LEDR[8] = ~done_seen;//negate when busy
      end

      always_ff @(posedge clk) begin
            go_reg <= 1'b0
            key_pressed_d <= key_pressed;
            hold_cnt <= hold_cnt + 23'd1; //// long-press ticker 
            tick <= (hold_cnt == 23'd0)


            if (done) done_seen <= 1'b1; //count updates one cycle after address change
            if (done_seen) count_reg <= count;



            if (key_pressed[3] && !key_pressed_d[3]) begin
                  base_n <= {22'b0, SW}; //SW[9:0] as start value
                  offset <= 8'd0;
                  done_seen <= 1'b0;
                  count_reg <= 16'd0;
                  go_reg  <= 1'b1; // 1-cycle pulse
            end

            if (key_pressed[2] && !key_pressed_d[2]) begin
                  offset <= 8'd0;
            end


            if (done_seen) begin
                  // KEY[0]: increment (short press OR long press tick)
                  if ( (key_pressed[0] && !key_pressed_d[0]) || (key_pressed[0] && tick) ) begin
                        if (offset != 8'hFF) offset <= offset + 8'd1; // clamp
                  end

                  // KEY[1]: decrement (short press OR long press tick)
                  if ( (key_pressed[1] && !key_pressed_d[1]) || (key_pressed[1] && tick) ) begin
                        if (offset != 8'h00) offset <= offset - 8'd1; // clamp
                  end
            end


      end



      //-----------------------------------------
      //assign HEX0 = {KEY[2:0], KEY[3:0]};
      //assign HEX1 = SW[6:0];
      //assign HEX2 = {(n == 12'b0), (count == 16'b0) ^ KEY[1],
      //            go, done ^ KEY[0], SW[9:7]};
      //assign HEX3 = HEX0;
      //assign HEX4 = HEX1;
      //assign HEX5 = HEX2;
      //assign LEDR = SW;
      //assign go = KEY[0];
      //assign start = {SW[1:0], SW, SW, SW};
      //assign n = {SW[1:0], SW};
   
   
  
endmodule

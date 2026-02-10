// CSEE 4840 Lab 1: Run and Display Collatz Conjecture Iteration Counts
//
// Spring 2023
//
// By: <your name here>
// Uni: <your uni here>

module lab1( input logic CLOCK_50,  // 50 MHz Clock input
             input logic [3:0]  KEY, // Pushbuttons; KEY[0] is rightmost (active-low)
             input logic [9:0]  SW,  // Switches; SW[0] is rightmost
             output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
             output logic [9:0] LEDR
             );

   logic clk, go, done;
   logic [31:0] start;
   logic [15:0] count;

   logic [11:0] n;

   assign clk = CLOCK_50;

   range #(256, 8) r ( .* ); // connects clk/go/start/done/count by name

   // ----------------------------
   // UI regs
   // ----------------------------
   logic [31:0] base_n;
   logic [7:0]  offset;
   logic        done_seen;

   // edge detect keys (pressed=1 when down)
   logic [3:0]  key_pressed, key_pressed_d;

   // long press tick (~6 Hz, acceptable for "about 5/sec")
   logic [22:0] hold_cnt;
   logic        tick;

   // go pulse generation (delayed 1 cycle)
   logic go_reg;
   logic go_pending;

   // robust done edge detection
   logic done_d;
   logic ui_running;

   // display helpers
   logic [31:0] cur_n;
   logic [11:0] n12;
   logic [11:0] c12;

   assign key_pressed = ~KEY; // KEY is active-low on DE1-SoC
   assign go = go_reg;

   // start mux: before done -> base_n; after done -> RAM address (offset)
   always_comb begin
      start = done_seen ? {24'b0, offset} : base_n;
   end

   assign cur_n = base_n + {24'b0, offset};
   assign n12   = cur_n[11:0];
   assign n     = n12;

   // show count only after done_seen; before that show 000
   assign c12 = done_seen ? count[11:0] : 12'h000;

   // LEDs: SW + status
   always_comb begin
      LEDR    = SW;
      LEDR[9] = done_seen;   // ready
      LEDR[8] = ~done_seen;  // busy

      // Optional debug (LED0 go is too fast to see by eye, but keep if you want):
      // LEDR[0] = go;
      // LEDR[1] = done;
   end

   // ----------------------------
   // Sequential UI logic
   // ----------------------------
   always_ff @(posedge clk) begin
      // defaults
      go_reg <= 1'b0;

      // sample key history for edge detect
      key_pressed_d <= key_pressed;

      // tick generator
      hold_cnt <= hold_cnt + 23'd1;
      tick <= (hold_cnt == 23'd0);

      // done edge detect
      done_d <= done;

      // emit go pulse one cycle after KEY3 edge
      if (go_pending) begin
         go_reg <= 1'b1;
         go_pending <= 1'b0;
         ui_running <= 1'b1;
      end

      // latch completion ONLY on rising edge of done, and only if we started a run
      if (ui_running && done && !done_d) begin
         done_seen  <= 1'b1;
         ui_running <= 1'b0;
      end

      // KEY[3] press edge: start a new run
      if (key_pressed[3] && !key_pressed_d[3]) begin
         base_n     <= {22'b0, SW}; // latch SW[9:0]
         offset     <= 8'd0;
         done_seen  <= 1'b0;
         go_pending <= 1'b1;

         // reset run bookkeeping so stale done can't instantly "complete"
         ui_running <= 1'b0;
         done_d     <= 1'b0;
      end

      // KEY[2] press edge: reset offset
      if (key_pressed[2] && !key_pressed_d[2]) begin
         offset <= 8'd0;
      end

      // browse results only after done
      if (done_seen) begin
         // KEY[0] increment
         if ( (key_pressed[0] && !key_pressed_d[0]) || (key_pressed[0] && tick) ) begin
            if (offset != 8'hFF) offset <= offset + 8'd1; // clamp
         end

         // KEY[1] decrement
         if ( (key_pressed[1] && !key_pressed_d[1]) || (key_pressed[1] && tick) ) begin
            if (offset != 8'h00) offset <= offset - 8'd1; // clamp
         end
      end
   end

   // ----------------------------
   // 7-seg wiring:
   // HEX5 HEX4 HEX3 = n (low 12 bits)
   // HEX2 HEX1 HEX0 = count (low 12 bits)
   // ----------------------------
   hex7seg hn0(.a(n12[3:0]),  .y(HEX3));
   hex7seg hn1(.a(n12[7:4]),  .y(HEX4));
   hex7seg hn2(.a(n12[11:8]), .y(HEX5));

   hex7seg hc0(.a(c12[3:0]),  .y(HEX0));
   hex7seg hc1(.a(c12[7:4]),  .y(HEX1));
   hex7seg hc2(.a(c12[11:8]), .y(HEX2));

endmodule


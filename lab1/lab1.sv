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

      // ----------------------------
      // UI regs
      // ----------------------------
      logic [31:0] base_n = 32'd0;
      logic [7:0]  offset;
      logic        done_seen;



      


      logic [15:0] count_reg;

      // edge detect keys (pressed=1 when down; KEY is active-low)
      logic [3:0] key_pressed, key_pressed_d;
      assign key_pressed = ~KEY;

      // 1-cycle go pulse
      logic go_reg;
      assign go = go_reg;

      // display helpers
      logic [31:0] cur_n;
      logic [11:0] n12;
      logic [11:0] c12;

      // start mux: before done -> base_n; after done -> RAM address (offset)
      assign start = done_seen ? {24'b0, offset} : base_n;

      // compute displayed n
      assign cur_n = base_n + {24'b0, offset};
      assign n12   = cur_n[11:0];
      assign n     = n12;

      // display count (low 12 bits). During compute, show 000 (or change to 12'hFFF for blanking logic)
      assign c12   = done_seen ? count_reg[11:0] : 12'h000;

      // ----------------------------
      // LEDs: SW + status
      // ----------------------------
      always_comb begin
            LEDR    = SW;
            LEDR[9] = done_seen;   // 1 when results ready
            LEDR[8] = ~done_seen;  // 1 when busy
	
      end

      // ----------------------------
      // Long-press repeat (key0/key1)
      //  - short press always changes by exactly 1
      //  - long press: wait DELAY_CYCLES, then repeat at REPEAT_CYCLES
      // ----------------------------
      localparam int DELAY_CYCLES  = 50_000_000 / 4;   // 0.25s
      localparam int REPEAT_CYCLES = 50_000_000 / 10;  // 10 Hz

      logic [31:0] k0_delay_cnt, k0_rep_cnt;
      logic [31:0] k1_delay_cnt, k1_rep_cnt;
      logic        k0_repeating, k1_repeating;

      wire k0_rise = key_pressed[0] & ~key_pressed_d[0];
      wire k1_rise = key_pressed[1] & ~key_pressed_d[1];
      wire k2_rise = key_pressed[2] & ~key_pressed_d[2];
      wire k3_rise = key_pressed[3] & ~key_pressed_d[3];

      // ----------------------------
      // Sequential UI logic
      // ----------------------------
      always_ff @(posedge clk) begin
            // defaults
            go_reg <= 1'b0;

            // sample key history for edge detect
            key_pressed_d <= key_pressed;

            // mark done (once done goes high, we stay in "ready/browse" mode until next KEY3)
            if (done) begin
                  done_seen <= 1'b1;
            end

            // latch count whenever done_seen is true (range output is stable in READ mode)
            if (done_seen) begin
                  count_reg <= count;
            end

            // KEY3: start a new run (latch SW into base_n, clear offset, clear done flag, emit go)
            if (key_pressed[3]&&!key_pressed_d[3]&&!key_pressed[0]&&!key_pressed[1]) begin
                  base_n     <= {22'b0, SW}; // SW[9:0] as start value
                  offset     <= 8'd0;
                  done_seen  <= 1'b0;
		
                  // keep old count on display during compute OR clear it; choose one:
                  // count_reg  <= 16'd0;   // uncomment if you prefer HEX0-2 to show 000 while computing

                  go_reg     <= 1'b1;       // 1-cycle pulse

                  // reset long-press state
                  k0_delay_cnt <= 32'd0;  k0_rep_cnt <= 32'd0;  k0_repeating <= 1'b0;
                  k1_delay_cnt <= 32'd0;  k1_rep_cnt <= 32'd0;  k1_repeating <= 1'b0;
            end

            // KEY2: reset offset (works in both modes)
            if (key_pressed[2]&&!key_pressed_d[2]&&!key_pressed[0]&&!key_pressed[1]) begin
                  offset <= 8'd0;

            end

            // Browse results only after done
            if (done_seen) begin
                  // ---- KEY0: increment offset ----
                  if (!key_pressed[0]) begin
                        k0_delay_cnt <= 32'd0;
                        k0_rep_cnt   <= 32'd0;
                        k0_repeating <= 1'b0;
                  end else begin
                        if (k0_rise) begin
                              // short press: exactly one step
                              if (offset != 8'hFF) offset <= offset + 8'd1;
                              k0_delay_cnt <= 32'd0;
                              k0_rep_cnt   <= 32'd0;
                              k0_repeating <= 1'b0;
                        end else if (!k0_repeating) begin
                              // held: wait delay
                              if (k0_delay_cnt >= (DELAY_CYCLES-1)) begin
                                    k0_repeating <= 1'b1;
                                    k0_rep_cnt   <= 32'd0;
                              end else begin
                                    k0_delay_cnt <= k0_delay_cnt + 32'd1;
                              end
                        end else begin
                              // repeating
                              if (k0_rep_cnt >= (REPEAT_CYCLES-1)) begin
                                    if (offset != 8'hFF) offset <= offset + 8'd1;
                                    k0_rep_cnt <= 32'd0;
                              end else begin
                                    k0_rep_cnt <= k0_rep_cnt + 32'd1;
                              end
                        end
                  end

                  // ---- KEY1: decrement offset ----
                  if (!key_pressed[1]) begin
                        k1_delay_cnt <= 32'd0;
                        k1_rep_cnt   <= 32'd0;
                        k1_repeating <= 1'b0;
                  end else begin
                        if (k1_rise) begin
                              if (offset != 8'h00) offset <= offset - 8'd1;
                              k1_delay_cnt <= 32'd0;
                              k1_rep_cnt   <= 32'd0;
                              k1_repeating <= 1'b0;
                        end else if (!k1_repeating) begin
                              if (k1_delay_cnt >= (DELAY_CYCLES-1)) begin
                                    k1_repeating <= 1'b1;
                                    k1_rep_cnt   <= 32'd0;
                              end else begin
                                    k1_delay_cnt <= k1_delay_cnt + 32'd1;
                              end
                        end else begin
                              if (k1_rep_cnt >= (REPEAT_CYCLES-1)) begin
                                    if (offset != 8'h00) offset <= offset - 8'd1;
                                    k1_rep_cnt <= 32'd0;
                              end else begin
                                    k1_rep_cnt <= k1_rep_cnt + 32'd1;
                              end
                        end
                  end
            end else begin
                  // if not done, keep long-press state reset (prevents odd behavior if keys held early)
                  k0_delay_cnt <= 32'd0; k0_rep_cnt <= 32'd0; k0_repeating <= 1'b0;
                  k1_delay_cnt <= 32'd0; k1_rep_cnt <= 32'd0; k1_repeating <= 1'b0;
            end
      end

      // ----------------------------
      // 7-seg wiring:
      // HEX5 HEX4 HEX3 = n (low 12 bits)
      // HEX2 HEX1 HEX0 = count (low 12 bits)
      // ----------------------------
      hex7seg h_n0 (.a(n12[3:0]),  .y(HEX3));
      hex7seg h_n1 (.a(n12[7:4]),  .y(HEX4));
      hex7seg h_n2 (.a(n12[11:8]), .y(HEX5));

      hex7seg h_c0 (.a(c12[3:0]),  .y(HEX0));
      hex7seg h_c1 (.a(c12[7:4]),  .y(HEX1));
      hex7seg h_c2 (.a(c12[11:8]), .y(HEX2));

endmodule

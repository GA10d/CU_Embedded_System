// CSEE 4840 Lab 1: Run and Display Collatz Conjecture Iteration Counts
// Fixed version: Combines debouncing from lab1_OLD.sv with blinking LED from lab1.sv

module lab1(
    input  logic        CLOCK_50,
    input  logic [3:0]   KEY,   // active-low
    input  logic [9:0]   SW,
    output logic [6:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output logic [9:0]   LEDR
);

    logic clk, go, done;
    logic [31:0] start;
    logic [15:0] count;
    logic [11:0] n;

    assign clk = CLOCK_50;

    range #(256, 8) r ( .* ); // connects clk/go/start/count/done/n by name

    // ----------------------------
    // UI regs
    // ----------------------------
    logic [31:0] base_n   = 32'd0;
    logic [7:0]  offset   = 8'd0;
    logic        done_seen= 1'b0;
    logic [15:0] count_reg= 16'd0;

    // 1-cycle go pulse
    logic go_reg = 1'b0;
    assign go = go_reg;

    // display helpers
    logic [31:0] cur_n;
    logic [11:0] n12;
    logic [11:0] c12;

    // ----------------------------
    // BLINK GENERATOR (from lab1.sv)
    // ----------------------------
    localparam int BLINK_HALF_CYCLES = 25_000_000; // 0.5s @ 50MHz => 1Hz blink
    logic [$clog2(BLINK_HALF_CYCLES)-1:0] blink_cnt = '0;
    logic blink = 1'b0;

    // start mux: before done -> base_n; after done -> RAM address (offset)
    assign start = done_seen ? {24'b0, offset} : base_n;

    // compute displayed n
    assign cur_n = base_n + {24'b0, offset};
    assign n12   = cur_n[11:0];
    assign n     = n12;

    // display count (low 12 bits)
    assign c12   = count_reg[11:0];

    // ----------------------------
    // LEDs: SW + status with BLINK
    // ----------------------------
    always_comb begin
        LEDR    = SW;
        LEDR[9] = done_seen ? blink : 1'b0;  // blink when results ready
        LEDR[8] = ~done_seen;                 // 1 when busy
    end

    // ============================================================
    // Key sync + debounce (from lab1_OLD.sv - FIX for missed presses / false resets)
    // ============================================================
    logic [3:0] key_sync1 = 4'b0, key_sync2 = 4'b0;
    logic [3:0] key_db    = 4'b0, key_db_d  = 4'b0; // debounced, pressed=1
    logic [31:0] db_cnt0 = 0, db_cnt1 = 0, db_cnt2 = 0, db_cnt3 = 0;

    localparam int DB_CYCLES = 50_000; // 1ms @ 50MHz

    always_ff @(posedge clk) begin
        // 2-FF synchronizer (pressed=1)
        key_sync1 <= ~KEY;
        key_sync2 <= key_sync1;

        // debounce each key (update key_db only after stable for DB_CYCLES)
        // KEY0
        if (key_sync2[0] == key_db[0]) db_cnt0 <= 0;
        else if (db_cnt0 == DB_CYCLES-1) begin key_db[0] <= key_sync2[0]; db_cnt0 <= 0; end
        else db_cnt0 <= db_cnt0 + 1;

        // KEY1
        if (key_sync2[1] == key_db[1]) db_cnt1 <= 0;
        else if (db_cnt1 == DB_CYCLES-1) begin key_db[1] <= key_sync2[1]; db_cnt1 <= 0; end
        else db_cnt1 <= db_cnt1 + 1;

        // KEY2
        if (key_sync2[2] == key_db[2]) db_cnt2 <= 0;
        else if (db_cnt2 == DB_CYCLES-1) begin key_db[2] <= key_sync2[2]; db_cnt2 <= 0; end
        else db_cnt2 <= db_cnt2 + 1;

        // KEY3
        if (key_sync2[3] == key_db[3]) db_cnt3 <= 0;
        else if (db_cnt3 == DB_CYCLES-1) begin key_db[3] <= key_sync2[3]; db_cnt3 <= 0; end
        else db_cnt3 <= db_cnt3 + 1;

        // history for edge detect (debounced)
        key_db_d <= key_db;
    end

    wire k0_rise = key_db[0] & ~key_db_d[0];
    wire k1_rise = key_db[1] & ~key_db_d[1];
    wire k2_rise = key_db[2] & ~key_db_d[2];
    wire k3_rise = key_db[3] & ~key_db_d[3];

    // ----------------------------
    // Long-press repeat (key0/key1)
    // ----------------------------
    localparam int DELAY_CYCLES  = 50_000_000 / 4;   // 0.25s
    localparam int REPEAT_CYCLES = 50_000_000 / 10;  // 10 Hz

    logic [31:0] k0_delay_cnt = 0, k0_rep_cnt = 0;
    logic [31:0] k1_delay_cnt = 0, k1_rep_cnt = 0;
    logic        k0_repeating = 0, k1_repeating = 0;

    // ----------------------------
    // Sequential UI logic with BLINK UPDATE
    // ----------------------------
    always_ff @(posedge clk) begin
        // defaults
        go_reg <= 1'b0;

        // ----------------------------
        // BLINK UPDATE (from lab1.sv)
        // ----------------------------
        if (!done_seen) begin
            blink_cnt <= '0;
            blink     <= 1'b0;
        end else if (blink_cnt == BLINK_HALF_CYCLES-1) begin
            blink_cnt <= '0;
            blink     <= ~blink;
        end else begin
            blink_cnt <= blink_cnt + 1'b1;
        end

        // mark done / latch count in READ mode
        if (done) done_seen <= 1'b1;
        if (done_seen) begin
            count_reg <= count;
        end

        // KEY3 has highest priority: start a new run
        if (k3_rise) begin
            base_n    <= {22'b0, SW};
            offset    <= 8'd0;
            done_seen <= 1'b0;
            go_reg    <= 1'b1;

            // reset long-press state
            k0_delay_cnt <= 0; k0_rep_cnt <= 0; k0_repeating <= 0;
            k1_delay_cnt <= 0; k1_rep_cnt <= 0; k1_repeating <= 0;
        end
        else begin
            // KEY2: reset offset (next priority)
            if (k2_rise) begin
                offset <= 8'd0;
            end

            // Browse only after done
            if (done_seen) begin
                // ---- KEY0: increment offset ----
                if (!key_db[0]) begin
                    k0_delay_cnt <= 0;
                    k0_rep_cnt   <= 0;
                    k0_repeating <= 0;
                end else begin
                    if (k0_rise) begin
                        if (offset != 8'hFF) offset <= offset + 1;
                        k0_delay_cnt <= 0; k0_rep_cnt <= 0; k0_repeating <= 0;
                    end else if (!k0_repeating) begin
                        if (k0_delay_cnt >= (DELAY_CYCLES-1)) begin
                            k0_repeating <= 1'b1;
                            k0_rep_cnt   <= 0;
                        end else begin
                            k0_delay_cnt <= k0_delay_cnt + 1;
                        end
                    end else begin
                        if (k0_rep_cnt >= (REPEAT_CYCLES-1)) begin
                            if (offset != 8'hFF) offset <= offset + 1;
                            k0_rep_cnt <= 0;
                        end else begin
                            k0_rep_cnt <= k0_rep_cnt + 1;
                        end
                    end
                end

                // ---- KEY1: decrement offset ----
                if (!key_db[1]) begin
                    k1_delay_cnt <= 0;
                    k1_rep_cnt   <= 0;
                    k1_repeating <= 0;
                end else begin
                    if (k1_rise) begin
                        if (offset != 8'h00) offset <= offset - 1;
                        k1_delay_cnt <= 0; k1_rep_cnt <= 0; k1_repeating <= 0;
                    end else if (!k1_repeating) begin
                        if (k1_delay_cnt >= (DELAY_CYCLES-1)) begin
                            k1_repeating <= 1'b1;
                            k1_rep_cnt   <= 0;
                        end else begin
                            k1_delay_cnt <= k1_delay_cnt + 1;
                        end
                    end else begin
                        if (k1_rep_cnt >= (REPEAT_CYCLES-1)) begin
                            if (offset != 8'h00) offset <= offset - 1;
                            k1_rep_cnt <= 0;
                        end else begin
                            k1_rep_cnt <= k1_rep_cnt + 1;
                        end
                    end
                end
            end
            else begin
                // not done: keep long-press state reset
                k0_delay_cnt <= 0; k0_rep_cnt <= 0; k0_repeating <= 0;
                k1_delay_cnt <= 0; k1_rep_cnt <= 0; k1_repeating <= 0;
            end
        end
    end

    // ----------------------------
    // 7-seg wiring:
    // HEX5 HEX4 HEX3 = n
    // HEX2 HEX1 HEX0 = count
    // ----------------------------
    hex7seg h_n0 (.a(n12[3:0]),  .y(HEX3));
    hex7seg h_n1 (.a(n12[7:4]),  .y(HEX4));
    hex7seg h_n2 (.a(n12[11:8]), .y(HEX5));

    hex7seg h_c0 (.a(c12[3:0]),  .y(HEX0));
    hex7seg h_c1 (.a(c12[7:4]),  .y(HEX1));
    hex7seg h_c2 (.a(c12[11:8]), .y(HEX2));

endmodule
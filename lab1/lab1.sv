// CSEE 4840 Lab 1: Run and Display Collatz Conjecture Iteration Counts
//
// Spring 2023
//
// By: <your name here>
// Uni: <your uni here>

module lab1(
    input  logic        CLOCK_50,  // 50 MHz Clock input
    input  logic [3:0]  KEY,        // Pushbuttons; KEY[0] is rightmost (active-low)
    input  logic [9:0]  SW,         // Switches; SW[0] is rightmost
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, // HEX0 rightmost
    output logic [9:0]  LEDR        // LEDR[0] rightmost
);

    // Signals that connect to range module (names must match for r(.*))
    logic        clk, go, done;
    logic [31:0] start;
    logic [15:0] count;

    // Displayed n (low 12 bits)
    logic [11:0] n;

    assign clk = CLOCK_50;

    // Range module (provided/implemented elsewhere)
    range #(256, 8) r ( .* );

    // ----------------------------
    // UI registers
    // ----------------------------
    logic [31:0] base_n;        // latched from SW when starting
    logic [7:0]  offset;        // 0..255
    logic        done_seen;     // latched done
    logic [15:0] count_reg;     // registered count for stable display

    // KEY is active-low on DE1-SoC: pressed == 0
    logic [3:0]  key_pressed, key_pressed_d;

    // Long-press tick (~6 Hz using 23-bit wrap; acceptable for "about 5/sec")
    logic [22:0] hold_cnt;
    logic        tick;

    // go pulse generation (delayed 1 cycle so start/base_n is stable)
    logic        go_reg;
    logic        go_pending;

    // Display helpers
    logic [31:0] cur_n;
    logic [11:0] n12;
    logic [11:0] c12;

    // pressed=1 when button down
    assign key_pressed = ~KEY;

    // Drive range.go
    assign go = go_reg;

    // After done, start becomes RAM address; before done, start is base_n
    always_comb begin
        start = done_seen ? {24'b0, offset} : base_n;
    end

    // Current displayed n = base_n + offset
    assign cur_n = base_n + {24'b0, offset};
    assign n12   = cur_n[11:0];
    assign n     = n12;

    // Count to display comes from registered count
    assign c12   = count_reg[11:0];

    // LEDs: show switches plus status
    always_comb begin
        LEDR    = SW;
        LEDR[9] = done_seen;     // ready
        LEDR[8] = ~done_seen;    // busy
        // Optional debug (uncomment if needed):
        // LEDR[0] = go;
        // LEDR[1] = done;
    end

    // ----------------------------
    // Sequential logic
    // ----------------------------
    always_ff @(posedge clk) begin
        // default: no go unless we pulse it
        go_reg <= 1'b0;

        // edge detect sampling
        key_pressed_d <= key_pressed;

        // long-press ticker
        hold_cnt <= hold_cnt + 23'd1;
        tick <= (hold_cnt == 23'd0);

        // If pending, emit a 1-cycle go pulse THIS cycle
        if (go_pending) begin
            go_reg <= 1'b1;
            go_pending <= 1'b0;
        end

        // latch done when range finishes
        if (done) done_seen <= 1'b1;

        // after done, register count (note: count valid 1 cycle after address change)
        if (done_seen) count_reg <= count;

        // KEY[3]: start range (press edge)
        // IMPORTANT: latch base_n first, then pulse go on next cycle (go_pending)
        if (key_pressed[3] && !key_pressed_d[3]) begin
            base_n     <= {22'b0, SW};  // SW[9:0] as base
            offset     <= 8'd0;
            done_seen  <= 1'b0;
            count_reg  <= 16'd0;
            go_pending <= 1'b1;         // go will pulse next cycle
        end

        // KEY[2]: reset offset (press edge)
        if (key_pressed[2] && !key_pressed_d[2]) begin
            offset <= 8'd0;
        end

        // Only allow browsing after done
        if (done_seen) begin
            // KEY[0]: increment (short press OR long-press tick)
            if ( (key_pressed[0] && !key_pressed_d[0]) || (key_pressed[0] && tick) ) begin
                if (offset != 8'hFF) offset <= offset + 8'd1; // clamp
            end

            // KEY[1]: decrement (short press OR long-press tick)
            if ( (key_pressed[1] && !key_pressed_d[1]) || (key_pressed[1] && tick) ) begin
                if (offset != 8'h00) offset <= offset - 8'd1; // clamp
            end
        end
    end

    // ----------------------------
    // 7-seg display wiring
    // Left 3 HEX show n (low 12 bits): HEX5 HEX4 HEX3
    // Right 3 HEX show count (low 12 bits): HEX2 HEX1 HEX0
    // ----------------------------
    hex7seg hn0(.a(n12[3:0]),  .y(HEX3));
    hex7seg hn1(.a(n12[7:4]),  .y(HEX4));
    hex7seg hn2(.a(n12[11:8]), .y(HEX5));

    hex7seg hc0(.a(c12[3:0]),  .y(HEX0));
    hex7seg hc1(.a(c12[7:4]),  .y(HEX1));
    hex7seg hc2(.a(c12[11:8]), .y(HEX2));

endmodule

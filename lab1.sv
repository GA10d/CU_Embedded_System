// CSEE 4840 Lab 1: Run and Display Collatz Conjecture Iteration Counts
//
// Spring 2023
//
// By: <your name here>
// Uni: <your uni here>

module lab1(
    input  logic        CLOCK_50,  // 50 MHz Clock input
    input  logic [3:0]  KEY,        // Pushbuttons; KEY[0] is rightmost (active-low on DE1-SoC)
    input  logic [9:0]  SW,         // Switches; SW[0] is rightmost
    // 7-segment LED displays; HEX0 is rightmost
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output logic [9:0]  LEDR        // LEDs above the switches; LEDR[0] on right
);

    // -----------------------
    // Wires to range.sv core
    // -----------------------
    logic        clk, go, done;
    logic [31:0] start;
    logic [15:0] count;

    assign clk = CLOCK_50;

    // RAM_WORDS = 256, RAM_ADDR_BITS = 8
    range #(256, 8) r ( .* ); // Connect clk/go/start/done/count by name

    // -----------------------
    // UI / control registers
    // -----------------------
    logic [31:0] base_n   = 32'd0;  // starting n (from switches)
    logic [7:0]  offset   = 8'd0;   // which entry to read back (0..255)
    logic        done_seen= 1'b0;   // latched "done" for UI
    logic [15:0] count_reg= 16'd0;  // stable copy of count for display

    logic [3:0]  key_pressed, key_pressed_d; // pressed==1 after invert
    logic [22:0] hold_cnt = 23'd0;
    logic        tick     = 1'b0;

    logic        go_reg   = 1'b0; // 1-cycle pulse for range.go

    // -----------------------
    // Display helpers
    // -----------------------
    logic [31:0] cur_n;   // n being displayed (base_n + offset)
    logic [11:0] n12;     // low 12 bits of n
    logic [11:0] c12;     // low 12 bits of count

    assign key_pressed = ~KEY; // DE1-SoC keys are active-low
    assign go          = go_reg;

    // During compute phase (done_seen==0), range expects start = base_n.
    // During read/display phase, range expects start = offset (address).
    assign start = done_seen ? {24'b0, offset} : base_n;

    // What we show on HEX3-HEX5: base_n + offset (low 12 bits)
    assign cur_n = base_n + {24'b0, offset};
    assign n12   = cur_n[11:0];

    // What we show on HEX0-HEX2: iteration count (low 12 bits)
    assign c12   = count_reg[11:0];

    // -----------------------
    // LEDs
    // -----------------------
    always_comb begin
        LEDR      = SW;
        LEDR[9]   = done_seen;   // 1 when results ready / read mode
        LEDR[8]   = ~done_seen;  // 1 when busy computing
    end

    // -----------------------
    // Key handling / long-press ticker / go pulse
    // -----------------------
    always_ff @(posedge clk) begin
        // defaults
        go_reg         <= 1'b0;
        key_pressed_d  <= key_pressed;

        // long-press tick (simple divider)
        hold_cnt <= hold_cnt + 23'd1;
        tick     <= (hold_cnt == 23'd0);

        // latch done (range.done is asserted in read mode)
        if (done) begin
            done_seen <= 1'b1;
        end

        // capture count for display only when in read mode
        if (done_seen) begin
            count_reg <= count;
        end

        // KEY[3]: start a new run (load base_n from switches, clear offset, clear done_seen)
        if (key_pressed[3] && !key_pressed_d[3]) begin
            base_n    <= {22'b0, SW}; // SW[9:0] as start value
            offset    <= 8'd0;
            done_seen <= 1'b0;
            count_reg <= 16'd0;
            go_reg    <= 1'b1;        // 1-cycle pulse
        end

        // KEY[2]: reset offset to 0 (only meaningful after done)
        if (key_pressed[2] && !key_pressed_d[2]) begin
            offset <= 8'd0;
        end

        // After done, KEY[0]/KEY[1] browse offset, short press or long press
        if (done_seen) begin
            // KEY[0]: increment offset
            if ( (key_pressed[0] && !key_pressed_d[0]) || (key_pressed[0] && tick) ) begin
                if (offset != 8'hFF) offset <= offset + 8'd1;
            end

            // KEY[1]: decrement offset
            if ( (key_pressed[1] && !key_pressed_d[1]) || (key_pressed[1] && tick) ) begin
                if (offset != 8'h00) offset <= offset - 8'd1;
            end
        end
    end

    // -----------------------
    // 7-seg display mapping
    // HEX5 HEX4 HEX3  HEX2 HEX1 HEX0
    //   n[11:8] n[7:4] n[3:0]   c[11:8] c[7:4] c[3:0]
    // -----------------------
    hex7seg h0(.a(c12[3:0]),   .y(HEX0));
    hex7seg h1(.a(c12[7:4]),   .y(HEX1));
    hex7seg h2(.a(c12[11:8]),  .y(HEX2));
    hex7seg h3(.a(n12[3:0]),   .y(HEX3));
    hex7seg h4(.a(n12[7:4]),   .y(HEX4));
    hex7seg h5(.a(n12[11:8]),  .y(HEX5));

endmodule

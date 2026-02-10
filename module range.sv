module range
  #(parameter
    RAM_WORDS      = 16,   // Number of counts to store in RAM
    RAM_ADDR_BITS  = 4,    // Number of RAM address bits
    // Debounce: at 50MHz, 18 bits ~ 2.6ms, 20 bits ~ 10.5ms
    DEBOUNCE_BITS  = 20
   )
   (input  logic         clk,    // Clock
    input  logic         go,     // KEY input (typically active-low)
    input  logic [31:0]  start,  // Number to start from or count to read
    output logic         done,   // True once memory is filled
    output logic [15:0]  count); // Iteration count once finished

  // ------------------------------------------------------------
  // 1) Synchronize + Debounce + Edge-detect for KEY press
  //    Assumption: KEY is active-low: pressed = 0.
  //    We create go_pulse = 1 for 1 cycle on a "press" event.
  // ------------------------------------------------------------

  logic go_meta, go_sync;
  always_ff @(posedge clk) begin
    go_meta <= go;
    go_sync <= go_meta;
  end

  // Convert to active-high "pressed" level
  logic go_pressed_level;
  assign go_pressed_level = ~go_sync; // pressed = 1

  // Debouncer: update debounced state only after stable for 2^DEBOUNCE_BITS cycles
  logic [DEBOUNCE_BITS-1:0] db_cnt = '0;
  logic go_db = 1'b0;          // debounced pressed level (active-high)
  logic go_db_prev = 1'b0;

  always_ff @(posedge clk) begin
    if (go_pressed_level == go_db) begin
      db_cnt <= '0;  // already matches debounced state, reset counter
    end else begin
      db_cnt <= db_cnt + 1'b1;
      if (&db_cnt) begin
        go_db <= go_pressed_level; // accept new stable state
        db_cnt <= '0;
      end
    end
    go_db_prev <= go_db;
  end

  // One-cycle pulse on press (0->1 transition of debounced pressed signal)
  logic go_pulse;
  assign go_pulse = go_db & ~go_db_prev;

  // ------------------------------------------------------------
  // 2) Collatz interface
  // ------------------------------------------------------------
  logic        cgo;    // "go" for the Collatz iterator (1-cycle pulse from FSM regs)
  logic        cdone;  // "done" from the Collatz iterator
  logic [31:0] n;      // number to start the Collatz iterator

  // verilator lint_off PINCONNECTEMPTY
  collatz c1(
    .clk (clk),
    .go  (cgo),
    .n   (n),
    .done(cdone),
    .dout()
  );

  // ------------------------------------------------------------
  // 3) RAM + addressing
  // ------------------------------------------------------------
  logic [RAM_ADDR_BITS-1:0] num;   // write address
  logic [15:0]              din;   // iteration counter to store
  logic [15:0]              mem[RAM_WORDS-1:0];

  // Make write-enable combinational to avoid "late we" issue
  typedef enum logic [2:0] {S_IDLE, S_PULSE, S_ITER, S_WRITE, S_NEXT, S_PRIME, S_READ} state_t;
  state_t state = S_IDLE;

  logic we;
  assign we = (state == S_WRITE);

  logic [RAM_ADDR_BITS-1:0] addr;
  assign addr = we ? num : start[RAM_ADDR_BITS-1:0];

  // running is combinational (no multi-driver)
  logic running;
  assign running = (state != S_IDLE) && (state != S_READ) && (state != S_PRIME);

  // ------------------------------------------------------------
  // 4) FSM
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    // defaults each cycle
    cgo  <= 1'b0;
    done <= 1'b0;

    case (state)

      S_IDLE: begin
        if (go_pulse) begin
          n     <= start;
          num   <= '0;
          din   <= 16'd1;
          cgo   <= 1'b1;      // request start (will be seen by collatz next cycle)
          state <= S_PULSE;
        end
      end

      // one-cycle spacer so the "cgo pulse" becomes a clean start event
      S_PULSE: begin
        state <= S_ITER;
      end

      S_ITER: begin
        if (cdone) begin
          state <= S_WRITE;   // next cycle will write din into RAM
        end else begin
          din <= din + 16'd1; // count cycles/iterations until done
        end
      end

      // In S_WRITE, we=1 (combinational), so RAM writes this same clock edge
      S_WRITE: begin
        if (num == {RAM_ADDR_BITS{1'b1}}) begin
          state <= S_PRIME;
        end else begin
          state <= S_NEXT;
        end
      end

      S_NEXT: begin
        n     <= n + 32'd1;
        num   <= num + {{(RAM_ADDR_BITS-1){1'b0}}, 1'b1};
        din   <= 16'd1;
        cgo   <= 1'b1;
        state <= S_PULSE;
      end

      S_PRIME: begin
        state <= S_READ;
      end

      S_READ: begin
        done  <= 1'b1;
        state <= S_READ;

        // restart on a NEW key press (pulse), not level
        if (go_pulse) begin
          n     <= start;
          num   <= '0;
          din   <= 16'd1;
          cgo   <= 1'b1;
          done  <= 1'b0;
          state <= S_PULSE;
        end
      end

      default: state <= S_IDLE;

    endcase
  end

  // ------------------------------------------------------------
  // 5) RAM write + synchronous read (1-cycle latency on count)
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (we) mem[addr] <= din;
    count <= mem[addr];
  end

endmodule

module range
   #(parameter
     RAM_WORDS = 16,            // Number of counts to store in RAM
     RAM_ADDR_BITS = 4)         // Number of RAM address bits
   (input logic         clk,    // Clock
    input logic         go,     // Read start and start testing
    input logic [31:0]  start,  // Number to start from or count to read
    output logic        done,   // True once memory is filled
    output logic [15:0] count); // Iteration count once finished

   // Collatz interface
   logic        cgo;     // "go" for the Collatz iterator
   logic        cdone;   // "done" from the Collatz iterator
   logic [31:0] n;       // number to start the Collatz iterator
   logic [31:0] dout;    // Collatz iteration value (unused by range)

   // Instantiate the Collatz iterator
   collatz c1(.clk(clk),
              .go(cgo),
              .n(n),
              .dout(dout),
              .done(cdone));

   // RAM write controls
   logic [RAM_ADDR_BITS - 1:0] num;   // The RAM address to write
   logic                       we;    // Write enable
   logic [15:0]                din;   // Data to write

   // RAM storage
   logic [15:0]                mem[RAM_WORDS - 1:0];
   logic [RAM_ADDR_BITS - 1:0] addr;  // Address to read/write

   // Address mux: write uses num; read uses start[...]
   assign addr = we ? num : start[RAM_ADDR_BITS-1:0];

   always_ff @(posedge clk) begin
      if (we) mem[addr] <= din;
      count <= mem[addr];
   end

   typedef enum logic [2:0] {S_IDLE, S_LAUNCH, S_RUN, S_WRITE, S_DONE} state_t;
   state_t state;

   logic [31:0] base_start;
   logic [15:0] iter_count;

   // n is always the current base + num; only sampled by collatz when cgo=1
   assign n = base_start + {{(32-RAM_ADDR_BITS){1'b0}}, num};

   // Combinational outputs from state
   always_comb begin
      cgo  = 1'b0;
      we   = 1'b0;
      din  = iter_count;
      done = 1'b0;

      unique case (state)
         S_LAUNCH: begin
            cgo = 1'b1;
         end

         S_WRITE: begin
            we  = 1'b1;
            din = iter_count;
         end

         S_DONE: begin
            done = 1'b1; 
         end
      endcase
   end

   always_ff @(posedge clk) begin
      unique case (state)

         S_IDLE: begin
            if (go) begin
               // restart
               base_start <= start;
               num        <= '0;
               iter_count <= 16'd0;
               state      <= S_LAUNCH;
            end
         end

         S_LAUNCH: begin
            // initialize counter to 1 (sequence length includes the starting value)
            iter_count <= 16'd1;
            state <= S_RUN;
         end

         S_RUN: begin
            if (!cdone) begin
               iter_count <= iter_count + 16'd1;
            end else begin
               state <= S_WRITE;
            end
         end

         S_WRITE: begin
            if (num == RAM_WORDS-1) begin
               state <= S_DONE;
            end else begin
               num <= num + 1'b1;
               state <= S_LAUNCH;
            end
         end

         S_DONE: begin
            // allow a new run anytime
            if (go) begin
               base_start <= start;
               num        <= '0;
               iter_count <= 16'd0;
               state      <= S_LAUNCH;
            end
         end

         default: begin
            state <= S_IDLE;
         end
      endcase
   end
   
   initial begin
      state      = S_IDLE;
      base_start = 32'd0;
      num        = '0;
      iter_count = 16'd0;
   end

endmodule


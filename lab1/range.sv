module range
   #(parameter
     RAM_WORDS = 16,            // Number of counts to store in RAM
     RAM_ADDR_BITS = 4)         // Number of RAM address bits
   (input logic         clk,    // Clock
    input logic 	go,     // Read start and start testing
    input logic [31:0] 	start,  // Number to start from or count to read
    output logic 	done,   // True once memory is filled
    output logic [15:0] count); // Iteration count once finished

   logic 		cgo;    // "go" for the Collatz iterator
   logic                cdone;  // "done" from the Collatz iterator
   logic [31:0] 	n;      // number to start the Collatz iterator

// verilator lint_off PINCONNECTEMPTY
   
   // Instantiate the Collatz iterator
   collatz c1(.clk(clk),
	      .go(cgo),
	      .n(n),
	      .done(cdone),
	      .dout());

   logic [RAM_ADDR_BITS - 1:0] 	 num;         // The RAM address to write
   logic 			 running = 0; // True during the iterations

   logic                       we;
   logic [15:0]                din;
   logic [15:0]                mem[RAM_WORDS - 1:0];
   logic [RAM_ADDR_BITS - 1:0] addr;

   assign addr = we ? num : start[RAM_ADDR_BITS-1:0];

   typedef enum logic [2:0] {S_IDLE, S_PULSE, S_ITER, S_WRITE, S_NEXT, S_PRIME, S_READ} state_t;
   state_t state = S_IDLE;

   assign running = (state != S_IDLE) && (state != S_READ) && (state != S_PRIME);

   always_ff @(posedge clk) begin
      cgo  <= 1'b0;
      we   <= 1'b0;
      done <= 1'b0;

      case (state)
         S_IDLE: begin
            if (go) begin
               n     <= start;
               num   <= '0;
               din   <= 16'd1;
               cgo   <= 1'b1;
               state <= S_PULSE;
            end
         end

         S_PULSE: begin
            state <= S_ITER;
         end

         S_ITER: begin
            if (cdone) begin
               state <= S_WRITE;
            end else begin
               din <= din + 16'd1;
            end
         end

         S_WRITE: begin
            we <= running;
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
            done <= 1'b1;
            state <= S_READ;  // keep done high is fine; if you need pulse, see below
            if (go) begin
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

   always_ff @(posedge clk) begin
      if (we) mem[addr] <= din;
      count <= mem[addr];
   end

endmodule

	     

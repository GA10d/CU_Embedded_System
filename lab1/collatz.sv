module collatz( input logic         clk,   // Clock
		input logic 	    go,    // Load value from n; start iterating
		input logic  [31:0] n,     // Start value; only read when go = 1
		output logic [31:0] dout,  // Iteration value: true after go = 1
		output logic 	    done); // True when dout reaches 1

   always_ff @(posedge clk) begin
      if (go) begin
         if (n == 1) begin
            dout <= 1;
            done <= 1;
         end else if (n % 2 == 0) begin
            dout <= n / 2;
         end else begin
            dout <= 3 * n + 1;
         end
      end else begin
         dout <= n; 
         done <= 0;
      end

   end

endmodule

module collatz( input logic         clk,   // Clock
		input logic 	    go,    // Load value from n; start iterating
		input logic  [31:0] n,     // Start value; only read when go = 1
		output logic [31:0] dout,  // Iteration value: true after go = 1
		output logic 	    done); // True when dout reaches 1

    always_ff @(posedge clk) begin
        if (go) begin
            dout <= n;
            done <= 1'b0;
        end else if (!done) begin
            if (dout == 32'd1) begin
                done <= 1'b1;            
            end else if (dout[0] == 1'b0) begin
                done <= (dout == 32'd2) ? 1'b1 : 1'b0;  
                dout <= dout >> 1;                  
            end else begin
                dout <= dout * 3 + 1;   
            end
        end
    end

endmodule

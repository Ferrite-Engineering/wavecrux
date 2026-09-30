// Clean-room sample ALU used by the RTL stems generation tests.
module alu (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] y
);
    always @(*) begin
        y = a + b;
    end
endmodule

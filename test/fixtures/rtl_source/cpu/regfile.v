// Clean-room sample register file used by the RTL stems generation tests.
module regfile (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] a,
    output reg  [7:0] b
);
    reg [7:0] mem [0:3];

    always @(posedge clk) begin
        if (!rst_n) begin
            a <= 8'd0;
            b <= 8'd0;
        end
    end
endmodule

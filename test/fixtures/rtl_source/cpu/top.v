// Clean-room sample design for RTL stems generation / source annotation tests.
// Top-level datapath wiring a register file into an ALU.
module top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  instr,
    output wire [7:0]  result
);
    wire [7:0] op_a;
    wire [7:0] op_b;
    wire [7:0] alu_out;

    regfile u_regfile (
        .clk   (clk),
        .rst_n (rst_n),
        .a     (op_a),
        .b     (op_b)
    );

    alu u_alu (
        .a (op_a),
        .b (op_b),
        .y (alu_out)
    );

    assign result = alu_out;
endmodule

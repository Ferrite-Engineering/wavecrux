// Clean-room generate-loop design for the AST stems-import tests.
// The named generate-for produces the unrolled scopes gen_blink[0..3] in
// the --json-only AST dump; each contains one blinker instance.
// (Comments here must not begin with the tool's own name — a comment whose
// first token matches it is parsed as a metacomment pragma and errors.)
module blinker(input wire clk, output reg led);
  always @(posedge clk) led <= ~led;
endmodule

module top(input wire clk, output wire [3:0] leds);
  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : gen_blink
      blinker u_blink(.clk(clk), .led(leds[i]));
    end
  endgenerate
endmodule

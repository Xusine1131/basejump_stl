// -------------------------------------------------------
// -- bsg_adder_carry_selected.v
// -------------------------------------------------------
// A Carry Selected Adder.
// -------------------------------------------------------
module bsg_adder_carry_selected #(
  parameter integer width_p = "inv"
)(
  input [width_p-1:0] a_i
  ,input [width_p-1:0] b_i
  ,input c_i
  ,output [width_p:0] o
);

wire [width_p:0] res_a = a_i + b_i;
wire [width_p:0] res_b = a_i + b_i + 1'b1;
assign o = c_i ? res_b : res_a;

endmodule

// -------------------------------------------------------
// -- bsg_adder_wallace_tree.v
// -- sqlin16@fudan.edu.cn
// -------------------------------------------------------
//  This is a wrapper of several frequently used configuration of wallace tree.
// -------------------------------------------------------


module bsg_adder_wallace_tree #(
  parameter integer width_p = "inv"
  ,parameter integer capacity_p = "inv"
  ,localparam integer output_size_lp = width_p + `BSG_SAFE_CLOG2(capacity_p)
)
(
  input [capacity_p-1:0][width_p-1:0] ops_i
  ,output [width_p-1:0] resA_o
  ,output [width_p-1:0] resB_o
);
  if(capacity_p == 8) begin
    bsg_adder_wallace_tree_8 #(
      .width_p(width_p)
    ) wt_8 (
      .ops_i(ops_i)
      ,.resA_o(resA_o)
      ,.resB_o(resB_o)
    );
  end
  else if(capacity_p == 16) begin
    bsg_adder_wallace_tree_16 #(
      .width_p(width_p)
    ) wt_16 (
      .ops_i(ops_i)
      ,.resA_o(resA_o)
      ,.resB_o(resB_o)
    );
  end
  else if(capacity_p == 32) begin
    bsg_adder_wallace_tree_32 #(
      .width_p(width_p)
    ) wt_32 (
      .ops_i(ops_i)
      ,.resA_o(resA_o)
      ,.resB_o(resB_o)
    );
  end
  else begin
    initial begin
      $error("There is no wallace tree with capacity = %d, but you can generate this module using \"bsg_adder_wallace_tree_generator.py %d\" ",capacity_p,capacity_p);
    end
  end
endmodule
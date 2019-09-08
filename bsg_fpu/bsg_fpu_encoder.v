// -------------------------------------------------------
// -- bsg_fpu_encoder.v
// -- 09/04/2019 sqlin16@fudan.edu.cn
// -------------------------------------------------------
// This module recover standard formation of IEEE 754 for intermediate representation of floating point numbers, which basically is a reciprocal of bsg_fpu_decoder.
// Generally, this module should be put as the last stage of fp. arithmetic pipeline.
// -------------------------------------------------------

module bsg_fpu_rounding #(
  parameter integer m_p = 23
)(
  input [m_p+2:0] i
  ,output logic [m_p-1:0] o
);

always_comb begin
  if(i[2] == 1'b0) o = i[m_p+2:3]; // less than half, truncate.
  else if(i[3] == 1'b1) o = i[m_p+2:3] + 1; // odd result, round to even.
  else if(i[1:0] == 2'b0) o = i[m_p+2:3]; // even condition, round to even.
  else o = {i[m_p+2:4], 1'b1}; // greater than half, carry.
end

endmodule


module bsg_fpu_encoder 
  import bsg_fpu_pkg::*;
#(
  parameter integer e_p = 8
  ,parameter integer m_p = 23
  ,localparam integer extended_exp_lp = `BSG_SAFE_CLOG2(m_p) > e_p ? `BSG_SAFE_CLOG2(m_p) : e_p + 1
)(
  input [extended_exp_lp-1:0] exp_i
  ,input [m_p:0] mantissa_i // 1.XXXXXXXXX
  ,input sign_i

  // specific condition
  ,input is_invalid_i
  ,input is_overflow_i
  ,input is_underflow_i
  ,output logic [e_p+m_p:0] o

  ,output logic invalid_o
  ,output logic overflow_o
  ,output logic underflow_o
);

wire need_correction = exp_i[extended_exp_lp-1] | (exp_i == '0);
// for subnormal number, 
wire [extended_exp_lp-1:0] abs_exp = -exp_i;
wire [m_p+2:0] shifted_mantissa = {mantissa_i[m_p:0],2'b0} >> abs_exp;
// determine the sticky bits
wire sticky_bit;
bsg_fpu_sticky #(
  .width_p(m_p+2)
) find_sticky (
  .i({mantissa_i[m_p:0],1'b0})
  ,.shamt_i(abs_exp[`BSG_WIDTH(m_p+3)-1:0])
  ,.sticky_o(sticky_bit)
);

wire [m_p+2:0] before_round_mantissa /*verilator public_flat*/ = {shifted_mantissa[m_p+2:1], sticky_bit};
wire [m_p-1:0] after_round_mantissa;

bsg_fpu_rounding #(
  .m_p(m_p)
) rounding (
  .i(before_round_mantissa)
  ,.o(after_round_mantissa)
);

always_comb begin
  if(is_invalid_i) begin
    o = `BSG_FPU_SIGNAN(e_p,m_p);
  end
  else if(is_overflow_i | (exp_i[extended_exp_lp-2:0] == '1 & ~exp_i[extended_exp_lp-1])) begin
    o = `BSG_FPU_INFTY(sign_i,e_p,m_p);
  end
  else if(is_underflow_i| (need_correction & abs_exp > m_p)) begin
    o = `BSG_FPU_ZERO(sign_i,e_p,m_p);
  end
  else if(need_correction) begin
    o = {sign_i, e_p'(0), after_round_mantissa};
  end
  else begin // Normal situation
    o = {sign_i, exp_i[e_p-1:0], mantissa_i[m_p-1:0]};
  end
end

assign invalid_o = is_invalid_i;
assign underflow_o = is_underflow_i| (need_correction & abs_exp > m_p);
assign overflow_o = is_overflow_i | (exp_i[extended_exp_lp-2:0] == '1 & ~exp_i[extended_exp_lp-1]);

endmodule

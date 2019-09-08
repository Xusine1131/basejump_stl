// -------------------------------------------------------
// -- bsg_fpu_decoder.v
// -- 09/03/2019  sqlin16@fudan.edu.cn 
// -------------------------------------------------------
// This is a decoder for IEEE 754 fp number, including:
// 1. normalize subnormal fp numbers.
// 2. split each part of normalized result.
// 3. evaluate the property of the input like bsg_fpu_preprocess.
// 
// At present this module is a combinatory circuit, and it's very convenient for pipelined fp ALU.  
// -------------------------------------------------------

module bsg_fpu_decoder #(
  parameter integer e_p = 8
  ,parameter integer m_p = 23
  ,localparam integer extended_exp_lp = `BSG_SAFE_CLOG2(m_p) > e_p ? `BSG_SAFE_CLOG2(m_p) : e_p + 1
)(
  input [e_p+m_p:0] a_i

  ,output logic zero_o
  ,output logic nan_o
  ,output logic sig_nan_o
  ,output logic infty_o
  ,output logic denormal_o
  ,output logic sign_o

  ,output logic [e_p:0] exp_o 
  ,output logic [m_p:0] man_o // 1.XXXXXXXXX
);

  wire [e_p-1:0] exp = a_i[e_p+m_p-1-:e_p];
  wire [m_p-1:0] man = a_i[m_p-1:0];
  assign sign_o = a_i[e_p+m_p];


  wire exp_zero = exp == '0;
  wire exp_one = exp == '1;
  wire man_zero = man == '0;

  // first, determine whether this the input is denormalized
  assign denormal_o = exp_zero & !man_zero;
  assign infty_o = exp_one & man_zero;
  assign nan_o = exp_one & !man_zero;
  assign sig_nan_o = nan_o & ~man[m_p-1];
  
  // Second, generate the normalized value.
  // generate leading zero
  logic [extended_exp_lp-1:0] leading_zeros_number;
  bsg_fpu_clz #(
    .width_p(m_p)
  ) clz (
    .i(man)
    ,.num_zero_o(leading_zeros_number[`BSG_SAFE_CLOG2(m_p)-1:0])
  );
  assign leading_zeros_number[extended_exp_lp-1:`BSG_SAFE_CLOG2(m_p)] = '0;
  // shifted by leading zero
  wire [m_p-1:0] normalized_m = man << leading_zeros_number;
  // exponent of the normalized value is -leading_zeros_number.
  // for instance, 0.0001011 * 2^(-126)
  // after shifted by leading zero, the value is 1.011 * 2^(-130), leading_zeros_number = 3, exp is regarded as -3
  wire [extended_exp_lp-1:0] shifted_exp = - leading_zeros_number;
  wire [m_p:0] shifted_mantissa = {normalized_m,1'b0};

  // Third, select the correct result.
  assign exp_o = denormal_o ? shifted_exp : {(extended_exp_lp-e_p)'(0), exp};
  assign man_o = denormal_o ? shifted_mantissa : {1'b1,man};

endmodule

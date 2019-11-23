// -------------------------------------------------------
// -- bsg_mul_iterative.v
// -------------------------------------------------------
// A radix-8 64-bit iterative booth multiplier.
// For the sake of PPA, only stride_p = 33 is supported, but you can use bsg_multiplier_compressor_generator.py  
// to generate the appropriate compressor you need.
// -------------------------------------------------------

module bsg_booth_encoder(
  input [3:0] i
  ,output [3:0] o
);
  assign o[2:0] = i[3] ? {~i[0], i[0], i[0]} - i[2:1]: {1'b0, i[0]} + i[2:1];
  // Note that -0 may cause problem because a sign modification term will be generate to fix the sign.
  assign o[3] = (i == '0) || (i == '1) ? '0 : i[3]; 
endmodule

module bsg_booth_selector_first #(
  parameter integer width_p = 64
)(
   input [width_p-1:0] mul_x1_i
  ,input mul_signed_i

  ,input [3:0] sel_i

  ,output [width_p+5:0] A_o
  ,output [width_p+5:0] B_o
);

logic [width_p+1:0] A_res;
logic [width_p+1:0] B_res;

assign A_res = {(width_p+2){sel_i[1]}} & {mul_signed_i, mul_x1_i, 1'b0};
assign B_res = {(width_p+2){sel_i[0]}} & {mul_signed_i, mul_signed_i, mul_x1_i};

wire [width_p+1:0] sel_res_A = sel_i[2] ? {mul_x1_i, 2'b00} : A_res;
wire [width_p+1:0] sel_res_B = B_res;

wire [width_p+1:0] selA_res_inv = sel_i[3] ? ~sel_res_A : sel_res_A;
wire [width_p+1:0] selB_res_inv = sel_i[3] ? ~sel_res_B : sel_res_B;

wire eA = (mul_signed_i && (sel_i[2:1] != '0)) ^ sel_i[3];
wire eB = (mul_signed_i && (sel_i[0] != '0)) ^ sel_i[3];

//wire [3:0] ext = {~e, e, e, e} - (sel_i[0] == 0 && sel_i[3]) - (sel_i[2:1] == '0 && sel_i[3]);
// eA = 0 : 1000 - 1 = 0111
// eA = 1 : 0111 - 1 = 0110

assign A_o = {3'b011, ~eA, selA_res_inv};
assign B_o = {3'b000, ~eB, selB_res_inv};


endmodule


module bsg_booth_selector_first_target #(
  parameter integer width_p = 64
)(
  // multiplicand
   input [width_p-1:0] mul_x1_i
  ,input [width_p+1:0] mul_x3_i
  ,input mul_signed_i // 1 indicate mul is negative

  // Select bit
  ,input [3:0] sel_i

  ,output [width_p+5:0] o // width+5
);

// select the basic result
logic [width_p+1:0] sel_res; // width + 2 
always_comb unique casez(sel_i[2:0])
  3'b000: sel_res = '0;
  3'b001: sel_res = {mul_signed_i, mul_signed_i, mul_x1_i};
  3'b010: sel_res = {mul_signed_i, mul_x1_i, 1'b0};
  3'b011: sel_res = mul_x3_i;
  3'b1??: sel_res = {mul_x1_i, 2'b0};
  default: sel_res = '0;
endcase
// Modify
wire [width_p+1:0] sel_res_inv = sel_i[3] ? ~sel_res : sel_res;
// Determine e
// wire e = mul_signed_i ^ sel_i[3];
wire e = (mul_signed_i && (sel_i[2:0] != '0)) ^ sel_i[3];
// Determine o
assign o = {~e, e, e, e, sel_res_inv};
endmodule

module bsg_booth_selector #(
  parameter integer width_p = 64
)(
  // multiplicand
   input [width_p-1:0] mul_x1_i
  ,input [width_p+1:0] mul_x3_i
  ,input mul_signed_i // 1 indicate mul is negative

  // Select bit
  ,input [3:0] sel_i

  ,output [width_p+4:0] o // width+5
);

// select the basic result
logic [width_p+1:0] sel_res; // width + 2 
always_comb unique casez(sel_i[2:0])
  3'b000: sel_res = '0;
  3'b001: sel_res = {mul_signed_i, mul_signed_i, mul_x1_i};
  3'b010: sel_res = {mul_signed_i, mul_x1_i, 1'b0};
  3'b011: sel_res = mul_x3_i;
  3'b1??: sel_res = {mul_x1_i, 2'b0};
  default: sel_res = '0;
endcase
// Modify
wire [width_p+1:0] sel_res_inv = sel_i[3] ? ~sel_res : sel_res;
// Determine e
// wire e = mul_signed_i ^ sel_i[3];
// 0, 1011, 0011
wire e = (mul_signed_i && (sel_i[2:0] != '0)) ^ sel_i[3];
// Determine o
assign o = {2'b11,~e, sel_res_inv};
endmodule


module bsg_mul_booth_compressor #(
  parameter integer width_p = 64
  ,parameter integer stride_p = 33
  ,localparam integer booth_recording_length_lp = width_p / 3
  ,localparam integer output_size_lp = `BSG_MIN(2*width_p, width_p+stride_p+6)
)(
  // multiplicand
  input  [width_p-1:0] mul_x1_i
  ,input [width_p+1:0] mul_x3_i
  ,input mul_signed_i

  ,input [booth_recording_length_lp-1:0][3:0] opB_i

  ,input [width_p+5:0] csaA_i
  ,input [width_p+5:0] csaB_i
  ,input sign_cor_i // This correction is from last iteration.
  ,input sign_cor_first_i // This correction is from the first Booth recording.

  ,output [output_size_lp-1:0] A_o
  ,output [output_size_lp-1:0] B_o
);

localparam term_size_lp = stride_p / 3;

wire [term_size_lp-1:0][width_p+4:0] partial_product_lo;
wire [term_size_lp-1:0] sign_correction;
wire [1:0][width_p+5:0] base_reg;
for(genvar i = 0; i < term_size_lp; ++i) begin: BOOTH_SELECTOR
  bsg_booth_selector #(
    .width_p(width_p)
    ) booth_selector (
    .mul_x1_i(mul_x1_i)
    ,.mul_x3_i(mul_x3_i)
    ,.mul_signed_i(mul_signed_i)

    ,.sel_i(opB_i[i])
    ,.o(partial_product_lo[i])
  );
  
  if (i == 0)
    assign sign_correction[i] = sign_cor_i;
  else 
    assign sign_correction[i] = opB_i[i-1][3];
end

assign base_reg[0] = csaA_i;
assign base_reg[1] = csaB_i;

bsg_multiplier_compressor_64_33 cps (
  .base_i(base_reg)
  ,.base_sign_i(sign_cor_first_i)
  //,.base_sign_i(1'b0)
  ,.psum_i(partial_product_lo)
  ,.sign_modification_i(sign_correction)
  ,.outA_o(A_o)
  ,.outB_o(B_o)
);

endmodule

module bsg_mul_iterative #(
  parameter integer width_p = 64
  ,parameter integer stride_p = 33
) (
  input clk_i
  ,input reset_i

  ,output ready_o

  ,input [width_p-1:0] opA_i
  ,input [width_p-1:0] opB_i
  ,input signed_i
  ,input v_i

  ,output [2*width_p-1:0] result_o
  ,output v_o
  ,input yumi_i
);

  initial begin
    $dumpfile("test.vcd");
    $dumpvars();
  end

  // Note that 3 must divide stride_p. 
  localparam booth_step_lp = stride_p / 3;
  // Calculate the length of booth encoding
  // width_p + 2: {sign_extension, opB_i}
  localparam booth_recording_length_lp = `BSG_CEIL(width_p + 1, 3);
  localparam extend_booth_recording_length_lp = booth_recording_length_lp * 3;
  // The first term is calculated in advance.
  localparam booth_recording_register_length_lp = booth_recording_length_lp-1;
  // How many turns it takes to generate partial sum?
  localparam gather_level_lp = `BSG_CEIL(booth_recording_register_length_lp, booth_step_lp);
  localparam last_shift_count_lp = width_p % stride_p ? width_p % stride_p : stride_p;

  typedef enum logic [2:0] {eIdle, ePre, eCal, eCPA, eDone} state_e;

  state_e state_r;
  wire calc_is_done;

  // FSM
  always_ff @(posedge clk_i) begin
    if(reset_i) state_r <= eIdle;
    else unique case(state_r)
      eIdle: if(v_i) state_r <= ePre;
      ePre: state_r <= eCal;
      eCal: if(calc_is_done) state_r <= eCPA;
      eCPA: state_r <= eDone;
      eDone: if(yumi_i) state_r <= eIdle;
    endcase
  end
  // Counter for eCal and eCPA. 
  reg [`BSG_SAFE_CLOG2(gather_level_lp)-1:0] state_cnt_r;
  // Counter update
  always_ff @(posedge clk_i) begin
    if(reset_i) begin
      state_cnt_r <= '0;
    end
    else if(state_r == eIdle && v_i) begin
      state_cnt_r <= '0;
    end
    else if(state_r == eCal) begin
      state_cnt_r <= state_cnt_r + 1;
    end
  end

  assign calc_is_done = state_cnt_r == (gather_level_lp-1);

  reg opA_signed_r;
  reg [width_p-1:0] opA_x1_r;
  // NOTE: for the sake of area, result_high_r and opA_x3_r are combined. 
  reg [width_p+1:0] result_high_r;

  reg [booth_recording_register_length_lp-1:0][3:0] opB_r;
  reg partial_sign_correction_r;
  reg first_partial_sign_correction_r;
  wire [booth_recording_length_lp-1:0][3:0] opB_n;

  wire opB_signed = signed_i & opB_i[width_p-1];
  localparam extension_sign_size_lp = extend_booth_recording_length_lp - width_p;
  wire [extend_booth_recording_length_lp:0] extend_opB_i = {{extension_sign_size_lp{opB_signed}}, opB_i, 1'b0};

  // Booth encoder
  for(genvar i = 0; i < booth_recording_length_lp; ++i) begin: BOOTH_ENCODER
    bsg_booth_encoder encoder(
      .i(extend_opB_i[3*i+:4])
      ,.o(opB_n[i])
    );
  end: BOOTH_ENCODER

  wire [booth_recording_register_length_lp-1:0][3:0] opB_update_n;

  if(stride_p != width_p) begin
    assign opB_update_n = {(booth_step_lp*4)'(0), opB_r[booth_recording_register_length_lp-1:booth_step_lp]};
  end
  else begin
      assign opB_update_n = '0;
  end

  always_ff @(posedge clk_i) begin // update for opA
    if(reset_i) begin
      opA_x1_r <= '0;
      opA_signed_r <= '0;
    end
    else unique case(state_r)
      eIdle: if(v_i) begin
        opA_x1_r <= opA_i;
        opA_signed_r <= opA_i[width_p-1] & signed_i;
      end
      default: begin

      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if(reset_i) begin
      opB_r <= '0;
      partial_sign_correction_r <= '0;
      first_partial_sign_correction_r <= '0;
    end
    else if(state_r == eIdle && v_i) begin
      opB_r <= opB_n[booth_recording_length_lp-1:1];
      partial_sign_correction_r <=  opB_n[0][3];
      first_partial_sign_correction_r <= opB_n[0][3];
    end
    else if(state_r == eCal) begin
      opB_r <= opB_update_n;
      first_partial_sign_correction_r <= '0;
      partial_sign_correction_r <= opB_r[booth_step_lp-1][3];
    end
  end

  // Partial Sum 
  // stride_p: for partial products which is most shifted. 
  // width_p + 1 + 2: the size of partial product.
  // 1: carry 
  localparam csa_reg_width_lp = stride_p + 6 + width_p;

  reg [csa_reg_width_lp-1:0] csa_opA_r;
  reg [csa_reg_width_lp-1:0] csa_opB_r;

  wire [csa_reg_width_lp-1:0] csa_opA_n;
  wire [csa_reg_width_lp-1:0] csa_opB_n;

  wire [width_p+5:0] csa_opA_init;
  wire [width_p+5:0] csa_opB_init;

  wire [width_p+5:0] csa_init = csa_opA_init + csa_opB_init + {opB_n[0][3],1'b0};
  wire [width_p+5:0] csa_init_expected;
  
  
  bsg_booth_selector_first #(
    .width_p(width_p)
  ) first_selector (
    .mul_x1_i(opA_x1_r)
    ,.mul_signed_i(opA_signed_r)
    ,.sel_i(opB_n[0])
    ,.A_o(csa_opA_init)
    ,.B_o(csa_opB_init)
  );
  
  wire [width_p+1:0] mul_x3;
  bsg_booth_selector_first_target #(
    .width_p(width_p)
  ) first_selector_expected (
    .mul_x1_i(opA_x1_r)
    ,.mul_x3_i(mul_x3)
    ,.mul_signed_i(opA_signed_r)

    ,.sel_i(opB_n[0])
    ,.o(csa_init_expected)
  );
  

  localparam csa_tree_width_lp = `BSG_MIN(csa_reg_width_lp, 2*width_p);

  wire [csa_tree_width_lp-1:0] aggregation_outA;
  wire [csa_tree_width_lp-1:0] aggregation_outB;
  // Setup aggregation units

  bsg_mul_booth_compressor #(
    .width_p(width_p)
    ,.stride_p(stride_p)
  ) compressor (
    .mul_x1_i(opA_x1_r)
    ,.mul_x3_i(result_high_r)
    ,.mul_signed_i(opA_signed_r)

    ,.opB_i(opB_r)

    ,.csaA_i(csa_opA_r[csa_reg_width_lp-1:stride_p])
    ,.csaB_i(csa_opB_r[csa_reg_width_lp-1:stride_p])
    ,.sign_cor_i(partial_sign_correction_r)
    ,.sign_cor_first_i(first_partial_sign_correction_r)

    ,.A_o(aggregation_outA)
    ,.B_o(aggregation_outB)
  );

  // Partial Adder for tail 
  wire [stride_p-1:0] tail_cpa_opA;
  wire [stride_p-1:0] tail_cpa_opB;
  wire tail_carry;
  wire [stride_p:0] tail_cpa_opt = tail_cpa_opA + tail_cpa_opB; 
  wire carry_to_cpa = tail_cpa_opt[last_shift_count_lp];
  assign tail_cpa_opA = state_r == eCPA ? csa_opA_r[last_shift_count_lp-1:0] : csa_opA_r[stride_p-1:0];
  assign tail_cpa_opB = state_r == eCPA  ? csa_opB_r[last_shift_count_lp-1:0] : csa_opB_r[stride_p-1:0];
  assign csa_opA_n = aggregation_outA;
  assign csa_opB_n = {aggregation_outB[csa_tree_width_lp-1:1], tail_cpa_opt[stride_p]};
  
  reg [width_p-1:0] result_low_r;
  wire [width_p-1:0] result_low_n;

  if(stride_p != width_p)
    assign result_low_n = state_r == eCPA  ? 
                    {tail_cpa_opt[last_shift_count_lp-1:0] , result_low_r[width_p-1:last_shift_count_lp]} :
                     {tail_cpa_opt[stride_p-1:0],result_low_r[width_p-1:stride_p]};
  else 
    assign result_low_n = tail_cpa_opt[stride_p-1:0];

  logic [width_p:0] cs_opA;
  logic [width_p:0] cs_opB;
  logic cs_car;
  logic [width_p+1:0] cs_res;
  assign mul_x3 = cs_res;

  bsg_adder_carry_selected #(
    .width_p(width_p+1)
  ) carry_selected (
    .a_i(cs_opA)
    ,.b_i(cs_opB)
    ,.c_i(cs_car)
    ,.o(cs_res)
  );

  always_comb unique case(state_r)
    ePre: begin
      cs_opA = {opA_x1_r,1'b0};
      cs_opB = {opA_signed_r, opA_x1_r};
      cs_car = '0;
    end
    default: begin
      cs_opA = csa_opA_r[csa_reg_width_lp-1:last_shift_count_lp];
      cs_opB = csa_opB_r[csa_reg_width_lp-1:last_shift_count_lp];
      cs_car = tail_cpa_opt[last_shift_count_lp];
    end
  endcase

  always_ff @(posedge clk_i) begin
    if(reset_i) begin
      csa_opA_r <= '0;
      csa_opB_r <= '0;
      result_low_r <= '0;
      result_high_r <= '0;
    end
    else unique case(state_r)
      eIdle: if(v_i) begin
        csa_opA_r <= '0;
        csa_opB_r <= '0;
        result_low_r <= '0;
        result_high_r <= '0;
      end
      ePre: begin
        csa_opA_r <= {csa_opA_init, stride_p'(0)};
        csa_opB_r <= {csa_opB_init, stride_p'(0)};
        result_low_r <= '0;
        result_high_r <= cs_res;
      end
      eCal: begin
        csa_opA_r <= csa_opA_n;
        csa_opB_r <= csa_opB_n;
        result_low_r <= result_low_n;
      end
      eCPA: begin
        result_low_r <= result_low_n;
        result_high_r <= cs_res;
        csa_opA_r <= csa_opA_r >> width_p;
        csa_opB_r <= csa_opB_r >> width_p;
      end
      default: begin

      end
    endcase
  end

  assign result_o = {result_high_r[width_p-1:0], result_low_r};
  assign v_o = state_r == eDone;
  assign ready_o = state_r == eIdle;

endmodule

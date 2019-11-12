// -------------------------------------------------------
// -- bsg_mul_iterative.v
// -------------------------------------------------------
// A radix-16 64-bit iterative booth multiplier.
// For the sake of PPA, only stride_p = 32 is supported, but you can use bsg_multiplier_compressor_generator.py  
// to generate the appropriate compressor you need.
// -------------------------------------------------------

module bsg_booth_encoder(
  input [4:0] i
  ,output [4:0] o
);
  assign o[3:0] = i[4] ? {~i[0], i[0], i[0], i[0]} - i[3:1]: {2'b0, i[0]} + i[3:1];
  assign o[4] = (i == '0) || (i == '1) ? '0 : i[4]; // Note that -0 may cause problem because a sign modification term will be generate to fix the sign.
endmodule

module bsg_booth_selector #(
  parameter integer width_p = 64
  ,parameter bit initial_p = 1'b0
)(
  // multiplicand
   input [width_p-1:0] mul_x1_i
  ,input [width_p+1:0] mul_x3_i
  ,input [width_p+2:0] mul_x5_i
  ,input [width_p+2:0] mul_x7_i
  ,input mul_signed_i // 1 indicate mul is negative

  // Select bit
  ,input [4:0] sel_i

  ,output [width_p+3+3+initial_p:0] o
);

// select the basic result
logic [width_p+2:0] sel_res;
always_comb unique casez(sel_i[3:0])
  4'd0: sel_res = '0;
  4'd1: sel_res = {mul_signed_i, mul_signed_i, mul_signed_i, mul_x1_i};
  4'd2: sel_res = {mul_signed_i, mul_signed_i, mul_x1_i, 1'b0};
  4'd3: sel_res = {mul_signed_i, mul_x3_i};
  4'd4: sel_res = {mul_signed_i, mul_x1_i, 2'b0};
  4'd5: sel_res = mul_x5_i;
  4'd6: sel_res = {mul_x3_i, 1'b0};
  4'd7: sel_res = mul_x7_i;
  4'b1???: sel_res = {mul_x1_i, 3'b0};
  default: sel_res = '0;
endcase
// Modify
wire [width_p+2:0] sel_res_inv = sel_i[4] ? ~sel_res : sel_res;
// Determine e
wire e = mul_signed_i ? sel_res_inv[width_p+2] : sel_i[4];
// Determine o
if(initial_p) begin: INITIAL_SEL
  assign o = {~e, e, e, e, e, sel_res_inv};
end
else begin: NORMAL_SEL
  assign o = {3'b111,~e, sel_res_inv};
end
endmodule


module bsg_mul_booth_compressor #(
  parameter integer width_p = 64
  ,parameter integer stride_p = 32
  ,localparam integer output_size_lp = `BSG_MAX(2*width_p, width_p+stride_p+8)
)(
  // multiplicand
  input  [width_p-1:0] mul_x1_i
  ,input [width_p+1:0] mul_x3_i
  ,input [width_p+2:0] mul_x5_i
  ,input [width_p+2:0] mul_x7_i
  ,input mul_signed_i

  ,input [4:0][width_p/4-1:0] opB_i

  ,input [width_p+7:0] csaA_i
  ,input [width_p+7:0] csaB_i
  ,input sign_cor_i // This correction is from last iteration.

  ,output [output_size_lp-1:0] A_o
  ,output [output_size_lp-1:0] B_o
);

localparam term_size_lp = stride_p / 4;

wire [term_size_lp-1:0][width_p+6:0] partial_product_lo;
wire [term_size_lp-1:0] sign_correction;
wire [1:0][width_p+7:0] base_reg;
for(genvar i = 0; i < term_size_lp; ++i) begin: BOOTH_SELECTOR
  bsg_booth_selector #(
    .width_p(width_p)
    ,.initial_p(0)
    ) booth_selector (
    .mul_x1_i(mul_x1_i)
    ,.mul_x3_i(mul_x3_i)
    ,.mul_x5_i(mul_x5_i)
    ,.mul_x7_i(mul_x7_i)
    ,.mul_signed_i(mul_signed_i)

    ,.sel_i({opB_i[4][i], opB_i[3][i], opB_i[2][i], opB_i[1][i], opB_i[0][i]})
    ,.o(partial_product_lo[i])
  );
  
  if (i == 0)
    assign sign_correction[i] = sign_cor_i;
  else 
    assign sign_correction[i] = opB_i[4][i-1];
end

assign base_reg[0] = csaA_i;
assign base_reg[1] = csaB_i;

bsg_multiplier_compressor_64_32 cps (
  .base_i(base_reg)
  ,.psum_i(partial_product_lo)
  ,.sign_modification_i(sign_correction)
  ,.outA_o(A_o)
  ,.outB_o(B_o)
);

endmodule

module bsg_mul_iterative #(
  parameter integer width_p = 64
  ,parameter integer stride_p = 32
  ,parameter integer cpa_stride_p = width_p
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
    //$dumpfile("test.vcd");
    //$dumpvars();
  end

  localparam cpa_level_lp = width_p / cpa_stride_p;
  localparam booth_step_lp = stride_p / 4;

  localparam gather_level_lp = width_p % stride_p ? width_p / stride_p + 1 : width_p / stride_p;
  localparam last_shift_count_lp = width_p % stride_p ? width_p % stride_p : stride_p;

  typedef enum logic [2:0] {eIdle, ePre, eCal, eCPA, eDone} state_e;

  state_e state_r;

  wire calc_is_done;
  wire cpa_is_done;

  // FSM
  always_ff @(posedge clk_i) begin
    if(reset_i) state_r <= eIdle;
    else unique case(state_r)
      eIdle: if(v_i) state_r <= ePre;
      ePre: state_r <= eCal;
      eCal: if(calc_is_done) state_r <= eCPA;
      eCPA: if(cpa_is_done) state_r <= eDone;
      eDone: if(yumi_i) state_r <= eIdle;
    endcase
  end
  // Counter for eCal and eCPA. 
  localparam state_cnt_size_lp = cpa_level_lp + gather_level_lp;
  reg [`BSG_SAFE_CLOG2(state_cnt_size_lp)-1:0] state_cnt_r;

  assign calc_is_done = state_cnt_r == (gather_level_lp-1);
  assign cpa_is_done = state_cnt_r == (state_cnt_size_lp-1);
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
    else if(state_r == eCPA) begin
      state_cnt_r <= state_cnt_r + 1;
    end
  end

  reg opA_signed_r;
  reg [width_p-1:0] opA_x1_r;
  reg [width_p+1:0] opA_x3_r; 
  wire [width_p+1:0] opA_x3_n = {opA_x1_r,1'b0} + {opA_signed_r, opA_x1_r};
  reg [width_p+2:0] opA_x5_r;
  wire [width_p+2:0] opA_x5_n = {opA_x1_r,2'b0} + {opA_signed_r, opA_signed_r, opA_x1_r};
  reg [width_p+2:0] opA_x7_r;
  wire [width_p+2:0] opA_x7_n = {opA_x1_r,3'b0} - {opA_signed_r, opA_signed_r, opA_signed_r, opA_x1_r};
  

  reg [4:0] [width_p/4-1:0] opB_r;
  reg partial_sign_correction_r;
  wire [4:0] [width_p/4:0] opB_n;

  wire opB_signed = signed_i & opB_i[width_p-1];
  wire [width_p+4:0] extend_opB_i = {{4{opB_signed}}, opB_i, 1'b0};

  // Booth encoder
  for(genvar i = 0; i <= width_p/4; ++i) begin
    bsg_booth_encoder encoder(
      .i(extend_opB_i[4*i+:5])
      ,.o({opB_n[4][i], opB_n[3][i], opB_n[2][i], opB_n[1][i], opB_n[0][i]})
    );
  end

  wire [4:0][width_p/4-1:0] opB_update_n;

  if(stride_p != width_p) begin
    for(genvar i = 0; i < 5; ++i)
      assign opB_update_n[i] = {booth_step_lp'(0),opB_r[i][width_p/4-1:booth_step_lp]};
  end
  else begin
    for(genvar i = 0; i < 5; ++i)
      assign opB_update_n[i] = booth_step_lp'(0);
  end

  always_ff @(posedge clk_i) begin // update for opA
    if(reset_i) begin
      opA_x1_r <= '0;
      opA_x3_r <= '0;
      opA_x5_r <= '0;
      opA_x7_r <= '0;
      opA_signed_r <= '0;
    end
    else unique case(state_r)
      eIdle: if(v_i) begin
        opA_x1_r <= opA_i;
        opA_signed_r <= opA_i[width_p-1] & signed_i;
      end
      ePre: begin
        opA_x3_r <= opA_x3_n;
        opA_x5_r <= opA_x5_n;
        opA_x7_r <= opA_x7_n;
      end
      default: begin

      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if(reset_i) begin
      opB_r <= '0;
      partial_sign_correction_r <= '0;
    end
    else if(state_r == eIdle && v_i) begin
      opB_r[0] <= opB_n[0][width_p/4:1];
      opB_r[1] <= opB_n[1][width_p/4:1];
      opB_r[2] <= opB_n[2][width_p/4:1];
      opB_r[3] <= opB_n[3][width_p/4:1];
      opB_r[4] <= opB_n[4][width_p/4:1];
      partial_sign_correction_r <= opB_n[4][0];
    end
    else if(state_r == eCal) begin
      opB_r <= opB_update_n;
      partial_sign_correction_r <= opB_r[4][booth_step_lp-1];
    end
  end

  // Partial Sum 
  // stride_p: for partial products which is most shifted. 
  // width_p + 1 + 2: the size of partial product.
  // 1: carry 
  localparam csa_reg_width_lp = stride_p + 8 + width_p;

  reg [csa_reg_width_lp-1:0] csa_opA_r;
  reg [csa_reg_width_lp-1:0] csa_opB_r;

  wire [csa_reg_width_lp-1:0] csa_opA_n;
  wire [csa_reg_width_lp-1:0] csa_opB_n;

  wire [width_p+7:0] csa_opA_init;

  bsg_booth_selector #(
    .width_p(width_p)
    ,.initial_p(1)
  ) first_selector (
    .mul_x1_i(opA_x1_r)
    ,.mul_x3_i(opA_x3_n)
    ,.mul_x5_i(opA_x5_n)
    ,.mul_x7_i(opA_x7_n)
    ,.mul_signed_i(opA_signed_r)
    ,.sel_i({opB_n[4][0], opB_n[3][0], opB_n[2][0], opB_n[1][0], opB_n[0][0]})
    ,.o(csa_opA_init)
  );

  localparam csa_tree_width_lp = `BSG_MAX(csa_reg_width_lp, 2*width_p);

  wire [csa_tree_width_lp-1:0] aggregation_outA;
  wire [csa_tree_width_lp-1:0] aggregation_outB;
  // Setup aggregation units

  bsg_mul_booth_compressor #(
    .width_p(width_p)
    ,.stride_p(stride_p)
  ) compressor (
    .mul_x1_i(opA_x1_r)
    ,.mul_x3_i(opA_x3_r)
    ,.mul_x5_i(opA_x5_r)
    ,.mul_x7_i(opA_x7_r)
    ,.mul_signed_i(opA_signed_r)

    ,.opB_i(opB_r)

    ,.csaA_i(csa_opA_r[csa_reg_width_lp-1:stride_p])
    ,.csaB_i(csa_opB_r[csa_reg_width_lp-1:stride_p])
    ,.sign_cor_i(partial_sign_correction_r)

    ,.A_o(aggregation_outA)
    ,.B_o(aggregation_outB)
  );

  // Partial Adder for tail 
  wire [stride_p-1:0] tail_cpa_opA;
  wire [stride_p-1:0] tail_cpa_opB;
  wire tail_carry;
  wire [stride_p:0] tail_cpa_opt = tail_cpa_opA + tail_cpa_opB; 
  wire carry_to_cpa = tail_cpa_opt[last_shift_count_lp];
  assign tail_cpa_opA = state_cnt_r == gather_level_lp ? csa_opA_r[last_shift_count_lp-1:0] : csa_opA_r[stride_p-1:0];
  assign tail_cpa_opB = state_cnt_r == gather_level_lp ? csa_opB_r[last_shift_count_lp-1:0] : csa_opB_r[stride_p-1:0];
  assign csa_opA_n = aggregation_outA;
  assign csa_opB_n = {aggregation_outB[csa_tree_width_lp-1:1], tail_cpa_opt[stride_p]};
  
  reg [width_p-1:0] result_low_r;
  wire [width_p-1:0] result_low_n;
  reg [width_p-1:0] result_high_r;
  wire [width_p:0] result_high_initial_n;
  wire [width_p:0] result_high_n;
  reg last_cpa_carry_r;

  if(stride_p != width_p)
    assign result_low_n = state_cnt_r == gather_level_lp ? 
                    {tail_cpa_opt[last_shift_count_lp-1:0] , result_low_r[width_p-1:last_shift_count_lp]} :
                     {tail_cpa_opt[stride_p-1:0],result_low_r[width_p-1:stride_p]};
  else 
    assign result_low_n = tail_cpa_opt[stride_p-1:0];

  // A carry selected adder 
  wire [cpa_stride_p:0] cpa_res_0 = {1'b0, csa_opA_r[last_shift_count_lp+:cpa_stride_p]} + {1'b0, csa_opB_r[last_shift_count_lp+:cpa_stride_p]};
  wire [cpa_stride_p:0] cpa_res_1 = {1'b0, csa_opA_r[last_shift_count_lp+:cpa_stride_p]} + {1'b0, csa_opB_r[last_shift_count_lp+:cpa_stride_p]} + 1;

  if(cpa_stride_p == width_p)
    assign result_high_initial_n = carry_to_cpa ? cpa_res_1 : cpa_res_0;
  else 
    assign result_high_initial_n = carry_to_cpa ? {cpa_res_1[cpa_stride_p:0],result_high_r[width_p-1:cpa_stride_p]} : {cpa_res_0[cpa_stride_p:0],result_high_r[width_p-1:cpa_stride_p]};

  if(cpa_stride_p == width_p) 
    assign result_high_n = carry_to_cpa ? cpa_res_1 : cpa_res_0;
  else 
    assign result_high_n = last_cpa_carry_r ? {cpa_res_1[cpa_stride_p:0],result_high_r[width_p-1:cpa_stride_p]} : {cpa_res_0[cpa_stride_p:0],result_high_r[width_p-1:cpa_stride_p]};

  always_ff @(posedge clk_i) begin
    if(reset_i) begin
      csa_opA_r <= '0;
      csa_opB_r <= '0;
      result_low_r <= '0;
      last_cpa_carry_r <= '0;
      result_high_r <= '0;
    end
    else if(state_r == eIdle && v_i) begin
      csa_opB_r <= '0;
      result_low_r <= '0;
      last_cpa_carry_r <= '0;
    end
    else if(state_r == ePre) begin
      csa_opA_r <= {csa_opA_init, stride_p'(0)};
    end
    else if(state_r == eCal) begin
      csa_opA_r <= csa_opA_n;
      csa_opB_r <= csa_opB_n;
      result_low_r <= result_low_n;
      last_cpa_carry_r <= '0;
    end
    else if(state_r == eCPA) begin
      if(state_cnt_r == gather_level_lp) begin
        result_low_r <= result_low_n;
        result_high_r <= result_high_initial_n[width_p-1:0];
        last_cpa_carry_r <= result_high_initial_n[width_p];
      end
      else begin
        result_high_r <= result_high_n[width_p-1:0];
        last_cpa_carry_r <= result_high_n[width_p];
      end
      csa_opA_r <= csa_opA_r >> cpa_stride_p;
      csa_opB_r <= csa_opB_r >> cpa_stride_p;
    end
  end

  assign result_o = {result_high_r, result_low_r};
  assign v_o = state_r == eDone;
  assign ready_o = state_r == eIdle;

endmodule

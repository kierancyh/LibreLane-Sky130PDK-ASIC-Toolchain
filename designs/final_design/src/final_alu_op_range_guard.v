`timescale 1ns/1ps
// V52C: range-guard physical cleanup after V52B.
//
// Purpose:
//   Determine whether the true scalar ADD/SUB/MUL result is outside
//   [-half_range, +half_range]. The RRNS datapath still computes the result.
//
// V52C physical changes:
//   1) Remove the saturating shifted-multiplicand datapath used by V50B..V52A.
//      The routed V52A reports showed one generated saturation condition
//      driving roughly twenty MUL next-state gates, causing the repeated
//      _07820_ max-slew/max-cap cluster.
//   2) Use a threshold/overflow-flag multiply guard instead. The shifted
//      multiplicand is no longer muxed between "shifted" and "all ones".
//      If it grows beyond half_range, a one-bit flag is set; a later selected
//      add reports range error. Comparator outputs now feed only small control
//      flags, not every bit of a wide register bank.
//   3) Use a small one-hot local FSM and reset only state/public outputs.
//      Internal multiply helper registers are loaded before use and are not
//      reset, avoiding reset fanout into the datapath.
module final_alu_op_range_guard #(
    parameter integer XW = 24,
    parameter integer PW = 20
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [1:0]               op_sel,
    input  wire signed [XW-1:0]     A_in,
    input  wire signed [XW-1:0]     B_in,
    input  wire [PW-1:0]            half_range,
    output reg                      done,
    output reg                      raw_range_error
);

    localparam [5:0]
        ST_IDLE      = 6'b000001,
        ST_MUL_CHECK = 6'b000010,
        ST_MUL_ADD   = 6'b000100,
        ST_MUL_SHIFT = 6'b001000,
        ST_MUL_DONE  = 6'b010000,
        ST_UNUSED    = 6'b100000;

    localparam [5:0] MUL_LAST_COUNT = PW[5:0];

    (* keep = "true", fsm_encoding = "none" *) reg [5:0] state;

    reg [PW:0] mul_acc_reg;
    reg [PW:0] mul_mcand_reg;
    reg [PW:0] mul_mult_reg;
    reg [5:0]  mul_count_reg;
    reg        mul_mcand_big_reg;

    wire signed [XW:0] add_true_wire = {A_in[XW-1], A_in} + {B_in[XW-1], B_in};
    wire signed [XW:0] sub_true_wire = {A_in[XW-1], A_in} - {B_in[XW-1], B_in};
    wire signed [XW:0] half_range_xw_wire = $signed({1'b0, {{(XW-PW){1'b0}}, half_range}});
    wire signed [XW:0] neg_half_range_xw_wire = -half_range_xw_wire;

    wire add_range_error_wire = (add_true_wire > half_range_xw_wire) ||
                                (add_true_wire < neg_half_range_xw_wire);
    wire sub_range_error_wire = (sub_true_wire > half_range_xw_wire) ||
                                (sub_true_wire < neg_half_range_xw_wire);

    wire [XW-1:0] a_abs_wire = A_in[XW-1] ? ((~A_in) + {{(XW-1){1'b0}}, 1'b1}) : A_in;
    wire [XW-1:0] b_abs_wire = B_in[XW-1] ? ((~B_in) + {{(XW-1){1'b0}}, 1'b1}) : B_in;
    wire [XW:0]   a_abs_ext_wire = {1'b0, a_abs_wire};
    wire [XW:0]   b_abs_ext_wire = {1'b0, b_abs_wire};
    wire [XW:0]   half_range_ext_wire = {{(XW+1-PW){1'b0}}, half_range};

    wire          a_zero_wire = (a_abs_wire == {XW{1'b0}});
    wire          b_zero_wire = (b_abs_wire == {XW{1'b0}});
    wire          a_gt_half_wire = (a_abs_ext_wire > half_range_ext_wire);
    wire          b_gt_half_wire = (b_abs_ext_wire > half_range_ext_wire);

    wire [PW:0]   half_range_pw_wire = {1'b0, half_range};
    wire [PW+1:0] half_range_cmp_wire = {1'b0, half_range_pw_wire};

    wire [PW+1:0] mul_acc_sum_wire = {1'b0, mul_acc_reg} + {1'b0, mul_mcand_reg};
    wire          mul_add_over_wire = mul_mcand_big_reg ||
                                      (mul_mcand_reg > half_range_pw_wire) ||
                                      (mul_acc_sum_wire > half_range_cmp_wire);

    wire [PW:0]   mul_mcand_shift_wire = {mul_mcand_reg[PW-1:0], 1'b0};
    wire [PW+1:0] mul_mcand_shift_ext_wire = {1'b0, mul_mcand_reg} << 1;
    wire          mul_mcand_shift_over_wire = mul_mcand_big_reg ||
                                             (mul_mcand_shift_ext_wire > half_range_cmp_wire);

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            done            <= 1'b0;
            raw_range_error <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        if (op_sel == 2'b00) begin
                            raw_range_error <= add_range_error_wire;
                            done            <= 1'b1;
                        end else if (op_sel == 2'b01) begin
                            raw_range_error <= sub_range_error_wire;
                            done            <= 1'b1;
                        end else if (op_sel == 2'b10) begin
                            mul_acc_reg       <= {(PW+1){1'b0}};
                            mul_count_reg     <= 6'd0;
                            mul_mcand_big_reg <= 1'b0;

                            if (a_zero_wire || b_zero_wire) begin
                                raw_range_error <= 1'b0;
                                done            <= 1'b1;
                            end else if (a_gt_half_wire || b_gt_half_wire) begin
                                raw_range_error <= 1'b1;
                                done            <= 1'b1;
                            end else begin
                                raw_range_error <= 1'b0;
                                mul_mcand_reg   <= a_abs_ext_wire[PW:0];
                                mul_mult_reg    <= b_abs_ext_wire[PW:0];
                                state           <= ST_MUL_CHECK;
                            end
                        end else begin
                            raw_range_error <= 1'b0;
                            done            <= 1'b1;
                        end
                    end
                end

                ST_MUL_CHECK: begin
                    /* V52C: no wide multiplier-zero early-exit comparator.
                     * The loop is bounded by mul_count_reg in ST_MUL_SHIFT.
                     */
                    if (mul_mult_reg[0]) begin
                        if (mul_add_over_wire) begin
                            raw_range_error <= 1'b1;
                            state           <= ST_MUL_DONE;
                        end else begin
                            state <= ST_MUL_ADD;
                        end
                    end else begin
                        state <= ST_MUL_SHIFT;
                    end
                end

                ST_MUL_ADD: begin
                    mul_acc_reg <= mul_acc_sum_wire[PW:0];
                    state       <= ST_MUL_SHIFT;
                end

                ST_MUL_SHIFT: begin
                    mul_mult_reg      <= {1'b0, mul_mult_reg[PW:1]};
                    mul_mcand_reg     <= mul_mcand_shift_wire;
                    mul_mcand_big_reg <= mul_mcand_shift_over_wire;

                    if (mul_count_reg == MUL_LAST_COUNT) begin
                        state <= ST_MUL_DONE;
                    end else begin
                        mul_count_reg <= mul_count_reg + 6'd1;
                        state         <= ST_MUL_CHECK;
                    end
                end

                ST_MUL_DONE: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

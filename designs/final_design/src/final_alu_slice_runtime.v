`timescale 1ns/1ps
// V19 source marker: small bit-serial modular slice, no wide signed reduce loop.
module final_alu_slice_runtime #(
    parameter integer WM = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [1:0]           op_sel,
    input  wire [WM-1:0]        a_res,
    input  wire [WM-1:0]        b_res,
    input  wire [WM-1:0]        modulus,
    output reg                  done,
    output reg  [WM-1:0]        z_res
);

    /*
     * V19 physical-signoff patch.
     *
     * The previous slice used a signed IW-wide repeated add/subtract reducer.
     * The routed V18 report showed its shared update condition driving a long
     * mux-select net for work_s/work_u bits.  Since runtime moduli are bounded
     * to 5 bits and encoder residues are canonical, the lane operation can be
     * done with a tiny modular datapath:
     *   ADD: one modular add
     *   SUB: one conditional add-back
     *   MUL: 5 cycles of shift/add modular multiplication
     *
     * Only state/done are reset.  Datapath registers are intentionally
     * reset-minimal to avoid reintroducing reset into wide self-hold muxes.
     */

    localparam [3:0]
        ST_IDLE    = 4'b0001,
        ST_ADD_SUB = 4'b0010,
        ST_MUL     = 4'b0100,
        ST_DONE    = 4'b1000;

    (* fsm_encoding = "none" *) reg [3:0] state;

    reg [1:0]    op_reg;
    reg [WM-1:0] a_reg;
    reg [WM-1:0] b_reg;
    reg [WM-1:0] mod_reg;
    reg [WM-1:0] acc_reg;
    reg [WM-1:0] mcand_reg;
    reg [WM-1:0] mult_reg;
    reg [2:0]    bit_count;

    wire [WM-1:0] add_res_wire;
    wire [WM-1:0] sub_res_wire;
    wire [WM-1:0] mul_acc_next_wire;
    wire [WM-1:0] mul_mcand_next_wire;

    function [WM-1:0] mod_add_once;
        input [WM-1:0] x;
        input [WM-1:0] y;
        input [WM-1:0] m;
        reg   [WM:0]   sum0;
        reg   [WM:0]   sum1;
        begin
            if (m == {WM{1'b0}}) begin
                mod_add_once = {WM{1'b0}};
            end else begin
                sum0 = {1'b0, x} + {1'b0, y};
                if (sum0 >= {1'b0, m})
                    sum1 = sum0 - {1'b0, m};
                else
                    sum1 = sum0;
                mod_add_once = sum1[WM-1:0];
            end
        end
    endfunction

    function [WM-1:0] mod_sub_once;
        input [WM-1:0] x;
        input [WM-1:0] y;
        input [WM-1:0] m;
        reg   [WM:0]   diff;
        begin
            if (m == {WM{1'b0}}) begin
                mod_sub_once = {WM{1'b0}};
            end else if (x >= y) begin
                diff = {1'b0, x} - {1'b0, y};
                mod_sub_once = diff[WM-1:0];
            end else begin
                diff = {1'b0, x} + {1'b0, m} - {1'b0, y};
                mod_sub_once = diff[WM-1:0];
            end
        end
    endfunction

    assign add_res_wire        = mod_add_once(a_reg, b_reg, mod_reg);
    assign sub_res_wire        = mod_sub_once(a_reg, b_reg, mod_reg);
    assign mul_acc_next_wire   = mult_reg[0] ? mod_add_once(acc_reg, mcand_reg, mod_reg) : acc_reg;
    assign mul_mcand_next_wire = mod_add_once(mcand_reg, mcand_reg, mod_reg);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        if (modulus == {WM{1'b0}})
                            state <= ST_DONE;
                        else if (op_sel == 2'b10)
                            state <= ST_MUL;
                        else
                            state <= ST_ADD_SUB;
                    end
                end

                ST_ADD_SUB: begin
                    state <= ST_DONE;
                end

                ST_MUL: begin
                    if (bit_count == (WM-1))
                        state <= ST_DONE;
                    else
                        state <= ST_MUL;
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        case (state)
            ST_IDLE: begin
                if (start) begin
                    op_reg    <= op_sel;
                    a_reg     <= a_res;
                    b_reg     <= b_res;
                    mod_reg   <= modulus;
                    acc_reg   <= {WM{1'b0}};
                    mcand_reg <= a_res;
                    mult_reg  <= b_res;
                    bit_count <= 3'd0;
                    if (modulus == {WM{1'b0}})
                        z_res <= {WM{1'b0}};
                end
            end

            ST_ADD_SUB: begin
                case (op_reg)
                    2'b00: z_res <= add_res_wire;
                    2'b01: z_res <= sub_res_wire;
                    default: z_res <= {WM{1'b0}};
                endcase
            end

            ST_MUL: begin
                acc_reg   <= mul_acc_next_wire;
                mcand_reg <= mul_mcand_next_wire;
                mult_reg  <= {1'b0, mult_reg[WM-1:1]};
                if (bit_count == (WM-1)) begin
                    z_res <= mul_acc_next_wire;
                end else begin
                    bit_count <= bit_count + 3'd1;
                end
            end

            default: begin
            end
        endcase
    end

endmodule

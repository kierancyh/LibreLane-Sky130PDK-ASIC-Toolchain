`timescale 1ns/1ps
`include "final_alu_cfg.svh"

module final_alu_encoder #(
    parameter WIDTH_IN = `FINAL_ALU_DATA_W,
    parameter M0 = `FINAL_ALU_BASE_MOD_0,
    parameter M1 = `FINAL_ALU_BASE_MOD_1,
    parameter M2 = `FINAL_ALU_BASE_MOD_2,
    parameter M3 = `FINAL_ALU_BASE_MOD_3,
    parameter M4 = `FINAL_ALU_RED_MOD_0,
    parameter M5 = `FINAL_ALU_RED_MOD_1,
    parameter CRNS_EN = 1
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               Encode_EN,
    input  wire signed [WIDTH_IN-1:0]         x,
    output wire                               Encode_Done,
    output wire signed [`FINAL_ALU_RES_W-1:0] base_r0,
    output wire signed [`FINAL_ALU_RES_W-1:0] base_r1,
    output wire signed [`FINAL_ALU_RES_W-1:0] base_r2,
    output wire signed [`FINAL_ALU_RES_W-1:0] base_r3,
    output wire signed [`FINAL_ALU_RES_W-1:0] red_r0,
    output wire signed [`FINAL_ALU_RES_W-1:0] red_r1
);

    function integer norm_std;
        input integer val;
        input integer m;
        begin
            norm_std = val % m;
            if (norm_std < 0)
                norm_std = norm_std + m;
        end
    endfunction

    function integer norm_bal;
        input integer val;
        input integer m;
        integer r;
        begin
            r = norm_std(val, m);
            if (r > (m / 2) || ((m % 2) == 0 && r == (m / 2)))
                r = r - m;
            norm_bal = r;
        end
    endfunction

    function integer enc_mod;
        input integer val;
        input integer m;
        begin
            enc_mod = CRNS_EN ? norm_bal(val, m) : norm_std(val, m);
        end
    endfunction

    // Hardening change:
    //   Keep residue generation purely combinational from the already-captured
    //   A_reg/B_reg values in final_alu_top. This removes the large Encode_EN
    //   broadcast from the encoder datapath and leaves Encode_EN as a tiny stage
    //   handshake only.
    assign base_r0 = enc_mod(x, M0);
    assign base_r1 = enc_mod(x, M1);
    assign base_r2 = enc_mod(x, M2);
    assign base_r3 = enc_mod(x, M3);
    assign red_r0  = enc_mod(x, M4);
    assign red_r1  = enc_mod(x, M5);

    // Stage-complete handshake only. No large internal fanout remains on this net.
    assign Encode_Done = Encode_EN;

    // Keep ports for compatibility with the existing benches and integration.
    wire _unused_ok = &{1'b0, clk, rst_n};

endmodule

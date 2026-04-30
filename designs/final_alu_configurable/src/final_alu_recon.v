`timescale 1ns/1ps
`include "final_alu_cfg.svh"

module final_alu_recon #(
    parameter OUT_WIDTH = `FINAL_ALU_DATA_W
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               Recon_Start,
    input  wire signed [`FINAL_ALU_RES_W-1:0] base_r0,
    input  wire signed [`FINAL_ALU_RES_W-1:0] base_r1,
    input  wire signed [`FINAL_ALU_RES_W-1:0] base_r2,
    input  wire signed [`FINAL_ALU_RES_W-1:0] base_r3,
    output reg  signed [OUT_WIDTH-1:0]        X_out,
    output reg                                Recon_Done
);

    localparam integer M      = `FINAL_ALU_M_BASE;
    localparam integer HALF_M = M / 2;

    localparam integer MOD0   = 3;
    localparam integer MOD1   = 5;
    localparam integer MOD2   = 7;
    localparam integer MOD3   = 11;

    localparam integer CRT_M0 = 385;
    localparam integer CRT_M1 = 231;
    localparam integer CRT_M2 = 165;
    localparam integer CRT_M3 = 105;

    localparam integer INV0   = 1;
    localparam integer INV1   = 1;
    localparam integer INV2   = 2;
    localparam integer INV3   = 2;

    reg [1:0]  x0_mod;
    reg [2:0]  x1_mod;
    reg [2:0]  x2_mod;
    reg [3:0]  x3_mod;
    reg [9:0]  term0;
    reg [9:0]  term1;
    reg [10:0] term2;
    reg [11:0] term3;
    reg [12:0] total;
    reg [10:0] total_mod;
    reg signed [10:0] total_centered;
    reg signed [OUT_WIDTH-1:0] X_next;
    reg start_d;

    function integer norm_mod;
        input integer x;
        input integer m;
        integer t;
        begin
            t = x % m;
            if (t < 0)
                t = t + m;
            norm_mod = t;
        end
    endfunction

    always @* begin
        x0_mod    = norm_mod(base_r0, MOD0);
        x1_mod    = norm_mod(base_r1, MOD1);
        x2_mod    = norm_mod(base_r2, MOD2);
        x3_mod    = norm_mod(base_r3, MOD3);

        term0     = x0_mod * CRT_M0 * INV0;
        term1     = x1_mod * CRT_M1 * INV1;
        term2     = x2_mod * CRT_M2 * INV2;
        term3     = x3_mod * CRT_M3 * INV3;

        total     = term0 + term1 + term2 + term3;
        total_mod = norm_mod(total, M);

        if (total_mod > HALF_M)
            total_centered = $signed({1'b0, total_mod}) - 12'sd1155;
        else
            total_centered = $signed({1'b0, total_mod});

        X_next = {{(OUT_WIDTH-11){total_centered[10]}}, total_centered};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            X_out      <= '0;
            Recon_Done <= 1'b0;
            start_d    <= 1'b0;
        end else begin
            Recon_Done <= start_d;
            start_d    <= Recon_Start;
            if (Recon_Start)
                X_out <= X_next;
        end
    end

endmodule

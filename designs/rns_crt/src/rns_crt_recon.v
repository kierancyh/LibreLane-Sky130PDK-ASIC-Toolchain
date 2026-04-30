`timescale 1ns/1ps

module rns_crt_recon #(
    parameter W0        = 2,
    parameter W1        = 3,
    parameter W2        = 3,
    parameter W3        = 4,
    parameter OUT_WIDTH = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 CRT_Start,
    input  wire [W0-1:0]        r0,
    input  wire [W1-1:0]        r1,
    input  wire [W2-1:0]        r2,
    input  wire [W3-1:0]        r3,
    output reg  [OUT_WIDTH-1:0] X_out,
    output reg                  CRT_Done
);

    localparam integer M    = 1155;

    localparam integer M0   = 385;
    localparam integer M1   = 231;
    localparam integer M2   = 165;
    localparam integer M3   = 105;

    localparam integer INV0 = 1;
    localparam integer INV1 = 1;
    localparam integer INV2 = 2;
    localparam integer INV3 = 2;

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

    reg [OUT_WIDTH-1:0] X_next;
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
        x0_mod    = norm_mod(r0, 3);
        x1_mod    = norm_mod(r1, 5);
        x2_mod    = norm_mod(r2, 7);
        x3_mod    = norm_mod(r3, 11);

        term0     = x0_mod * M0 * INV0;
        term1     = x1_mod * M1 * INV1;
        term2     = x2_mod * M2 * INV2;
        term3     = x3_mod * M3 * INV3;

        total     = term0 + term1 + term2 + term3;
        total_mod = norm_mod(total, M);

        X_next    = total_mod;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            CRT_Done <= 1'b0;
            start_d  <= 1'b0;
        end else begin
            CRT_Done <= start_d;
            start_d  <= CRT_Start;

            if (CRT_Start)
                X_out <= X_next;
        end
    end

endmodule
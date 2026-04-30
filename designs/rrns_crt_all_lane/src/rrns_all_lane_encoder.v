`timescale 1ns/1ps
module rrns_all_lane_encoder #(
    parameter WIDTH_IN = 16,

    parameter M0 = 3,
    parameter M1 = 5,
    parameter M2 = 7,
    parameter M3 = 11,
    parameter M4 = 13,
    parameter M5 = 17,

    parameter W0 = 2,
    parameter W1 = 3,
    parameter W2 = 3,
    parameter W3 = 4,
    parameter W4 = 4,
    parameter W5 = 5,

    // 1 = centered/balanced residues, 0 = standard residues
    parameter CRNS_EN = 1
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       Encode_EN,
    input  wire signed [WIDTH_IN-1:0] x,

    output reg                        Encode_Done,
    output reg signed [W0-1:0]        r0,
    output reg signed [W1-1:0]        r1,
    output reg signed [W2-1:0]        r2,
    output reg signed [W3-1:0]        r3,
    output reg signed [W4-1:0]        r4,
    output reg signed [W5-1:0]        r5
);

    integer tmp0, tmp1, tmp2, tmp3, tmp4, tmp5;

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

    always @(posedge clk) begin
        Encode_Done <= 1'b0;

        if (Encode_EN) begin
            tmp0 = CRNS_EN ? norm_bal(x, M0) : norm_std(x, M0);
            tmp1 = CRNS_EN ? norm_bal(x, M1) : norm_std(x, M1);
            tmp2 = CRNS_EN ? norm_bal(x, M2) : norm_std(x, M2);
            tmp3 = CRNS_EN ? norm_bal(x, M3) : norm_std(x, M3);
            tmp4 = CRNS_EN ? norm_bal(x, M4) : norm_std(x, M4);
            tmp5 = CRNS_EN ? norm_bal(x, M5) : norm_std(x, M5);

            r0 <= tmp0[W0-1:0];
            r1 <= tmp1[W1-1:0];
            r2 <= tmp2[W2-1:0];
            r3 <= tmp3[W3-1:0];
            r4 <= tmp4[W4-1:0];
            r5 <= tmp5[W5-1:0];

            Encode_Done <= 1'b1;
        end
    end

endmodule
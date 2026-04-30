`timescale 1ns/1ps
module crns_encoder #(
    parameter WIDTH_IN = 16,

    parameter M0 = 3,
    parameter M1 = 5,
    parameter M2 = 7,
    parameter M3 = 11,

    parameter W0 = 2,
    parameter W1 = 3,
    parameter W2 = 3,
    parameter W3 = 4,

    // 1 = centered/balanced residues, 0 = standard residues
    parameter CRNS_EN = 1
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       Encode_EN,

    // Signed so you can later test negative operands too
    input  wire signed [WIDTH_IN-1:0] x,

    output reg                        Encode_Done,

    // Centered residue outputs when CRNS_EN=1
    output reg signed [W0-1:0]        r0,
    output reg signed [W1-1:0]        r1,
    output reg signed [W2-1:0]        r2,
    output reg signed [W3-1:0]        r3
);

    integer tmp0, tmp1, tmp2, tmp3;

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

            // Matches your Python CRNS model behavior
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

            r0 <= tmp0[W0-1:0];
            r1 <= tmp1[W1-1:0];
            r2 <= tmp2[W2-1:0];
            r3 <= tmp3[W3-1:0];

            Encode_Done <= 1'b1;
        end
    end

endmodule
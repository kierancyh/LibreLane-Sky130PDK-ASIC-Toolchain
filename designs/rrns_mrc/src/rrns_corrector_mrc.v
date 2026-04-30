`timescale 1ns/1ps
module rrns_corrector_mrc #(
    parameter W0        = 2,
    parameter W1        = 3,
    parameter W2        = 3,
    parameter W3        = 4,
    parameter W4        = 4,
    parameter W5        = 5,
    parameter OUT_WIDTH = 16
)(
    input  wire signed [OUT_WIDTH-1:0] X_base,

    input  wire signed [W0-1:0]        r0,
    input  wire signed [W1-1:0]        r1,
    input  wire signed [W2-1:0]        r2,
    input  wire signed [W3-1:0]        r3,
    input  wire signed [W4-1:0]        r4, // mod 13
    input  wire signed [W5-1:0]        r5, // mod 17

    output reg  signed [OUT_WIDTH-1:0] X_corr,
    output reg                         Error_Detected,
    output reg                         Corrected,
    output reg                         Valid
);

    localparam integer M_BASE    = 1155;
    localparam integer HALF_BASE = M_BASE / 2;   // 577

    integer n0, n1, n2, n3, n4, n5;
    integer x_base_int;

    // Option A: single designated base-lane correction target only.
    // Keep only the drop-r3 / mod-11 recovery candidate.
    integer cand3_13;
    integer cand3_17;

    reg chk13;
    reg chk17;
    reg ok3_13;
    reg ok3_17;

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

    function integer center_with_modulus;
        input integer x;
        input integer p;
        integer t;
        begin
            t = norm_mod(x, p);
            if (t > (p / 2))
                center_with_modulus = t - p;
            else
                center_with_modulus = t;
        end
    endfunction

    function integer in_base_range;
        input integer x;
        begin
            in_base_range = (x >= -HALF_BASE) && (x <= HALF_BASE);
        end
    endfunction

    function integer red_ok;
        input integer x;
        input integer r;
        input integer m;
        begin
            red_ok = (norm_mod(x, m) == norm_mod(r, m));
        end
    endfunction

    always @* begin
        n0 = norm_mod(r0, 3);
        n1 = norm_mod(r1, 5);
        n2 = norm_mod(r2, 7);
        n3 = norm_mod(r3, 11);
        n4 = norm_mod(r4, 13);
        n5 = norm_mod(r5, 17);

        x_base_int = X_base;

        // Base-result checks against both redundant lanes
        chk13 = red_ok(x_base_int, n4, 13);
        chk17 = red_ok(x_base_int, n5, 17);

        // Single designated drop-r3 recovery candidate.
        // Use one included redundant lane and cross-check against the other.
        cand3_13 = center_with_modulus(
            (n0*455*2 + n1*273*2 + n2*195*6 + n4*105*1), 1365
        ); // [3,5,7,13], assumes r3/mod-11 is faulty

        cand3_17 = center_with_modulus(
            (n0*595*1 + n1*357*3 + n2*255*5 + n5*105*6), 1785
        ); // [3,5,7,17], assumes r3/mod-11 is faulty

        ok3_13 = red_ok(cand3_13, n5, 17) && in_base_range(cand3_13);
        ok3_17 = red_ok(cand3_17, n4, 13) && in_base_range(cand3_17);

        // Defaults
        X_corr         = X_base;
        Error_Detected = 1'b0;
        Corrected      = 1'b0;
        Valid          = 1'b1;

        // Decision logic:
        // 1) both checks pass -> clean
        // 2) exactly one check fails -> likely redundant-lane fault, keep base result
        // 3) both checks fail -> try only the designated r3 recovery path
        if (chk13 && chk17) begin
            X_corr         = X_base;
            Error_Detected = 1'b0;
            Corrected      = 1'b0;
            Valid          = 1'b1;

        end else if (chk13 ^ chk17) begin
            X_corr         = X_base;
            Error_Detected = 1'b1;
            Corrected      = 1'b1;  // tolerated redundant-lane fault
            Valid          = 1'b1;

        end else begin
            Error_Detected = 1'b1;

            // Not-overly-simplified Option A:
            // only accept r3-only base correction when BOTH independent
            // recovery paths are self-consistent and agree on the same value.
            if (ok3_13 && ok3_17 && (cand3_13 == cand3_17)) begin
                X_corr    = cand3_13[OUT_WIDTH-1:0];
                Corrected = 1'b1;
                Valid     = 1'b1;
            end else begin
                X_corr    = X_base;
                Corrected = 1'b0;
                Valid     = 1'b0;
            end
        end
    end

endmodule

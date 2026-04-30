`timescale 1ns/1ps
module rrns_all_lane_corrector_crt #(
    parameter W0        = 2,
    parameter W1        = 3,
    parameter W2        = 3,
    parameter W3        = 4,
    parameter W4        = 4,
    parameter W5        = 5,
    parameter OUT_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          Correct_Start,
    input  wire signed [OUT_WIDTH-1:0]   X_base,

    input  wire signed [W0-1:0]          r0,
    input  wire signed [W1-1:0]          r1,
    input  wire signed [W2-1:0]          r2,
    input  wire signed [W3-1:0]          r3,
    input  wire signed [W4-1:0]          r4,
    input  wire signed [W5-1:0]          r5,

    output reg  signed [W0-1:0]          corr_r0,
    output reg  signed [W1-1:0]          corr_r1,
    output reg  signed [W2-1:0]          corr_r2,
    output reg  signed [W3-1:0]          corr_r3,
    output reg                           Error_Detected,
    output reg                           Corrected,
    output reg                           Valid,
    output reg                           Correct_Done
);

    localparam integer M0        = 3;
    localparam integer M1        = 5;
    localparam integer M2        = 7;
    localparam integer M3        = 11;
    localparam integer M4        = 13;
    localparam integer M5        = 17;
    localparam integer M_BASE    = 1155;

    localparam [2:0]
        S_IDLE    = 3'd0,
        S_PREP    = 3'd1,
        S_EVAL    = 3'd2,
        S_RESOLVE = 3'd3,
        S_DONE    = 3'd4;

    reg [2:0] state;

    reg start_d;
    wire start_pulse = Correct_Start & ~start_d;

    reg [1:0] n0_r;
    reg [2:0] n1_r;
    reg [2:0] n2_r;
    reg [3:0] n3_r;
    reg [3:0] n4_r;
    reg [4:0] n5_r;

    reg       chk13_r;
    reg       chk17_r;

    reg [1:0] lane_idx_r;
    reg [3:0] cand_val_r;

    reg       winner_found_r;
    reg       conflict_found_r;
    reg [1:0] winner_lane_r;
    reg [3:0] winner_res_r;

    reg [1:0] b0_w;
    reg [2:0] b1_w;
    reg [2:0] b2_w;
    reg [3:0] b3_w;
    reg [3:0] exp13_w;
    reg [4:0] exp17_w;
    reg       hit_w;

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

    function [1:0] canon_r0;
        input signed [W0-1:0] x;
        begin
            case ($signed(x))
                -1: canon_r0 = 2'd2;
                 0: canon_r0 = 2'd0;
                 1: canon_r0 = 2'd1;
                default: canon_r0 = norm_mod($signed(x), M0);
            endcase
        end
    endfunction

    function [2:0] canon_r1;
        input signed [W1-1:0] x;
        begin
            case ($signed(x))
                -2: canon_r1 = 3'd3;
                -1: canon_r1 = 3'd4;
                 0: canon_r1 = 3'd0;
                 1: canon_r1 = 3'd1;
                 2: canon_r1 = 3'd2;
                default: canon_r1 = norm_mod($signed(x), M1);
            endcase
        end
    endfunction

    function [2:0] canon_r2;
        input signed [W2-1:0] x;
        begin
            case ($signed(x))
                -3: canon_r2 = 3'd4;
                -2: canon_r2 = 3'd5;
                -1: canon_r2 = 3'd6;
                 0: canon_r2 = 3'd0;
                 1: canon_r2 = 3'd1;
                 2: canon_r2 = 3'd2;
                 3: canon_r2 = 3'd3;
                default: canon_r2 = norm_mod($signed(x), M2);
            endcase
        end
    endfunction

    function [3:0] canon_r3;
        input signed [W3-1:0] x;
        begin
            case ($signed(x))
                -5: canon_r3 = 4'd6;
                -4: canon_r3 = 4'd7;
                -3: canon_r3 = 4'd8;
                -2: canon_r3 = 4'd9;
                -1: canon_r3 = 4'd10;
                 0: canon_r3 = 4'd0;
                 1: canon_r3 = 4'd1;
                 2: canon_r3 = 4'd2;
                 3: canon_r3 = 4'd3;
                 4: canon_r3 = 4'd4;
                 5: canon_r3 = 4'd5;
                default: canon_r3 = norm_mod($signed(x), M3);
            endcase
        end
    endfunction

    function [3:0] canon_r4;
        input signed [W4-1:0] x;
        begin
            case ($signed(x))
                -6: canon_r4 = 4'd7;
                -5: canon_r4 = 4'd8;
                -4: canon_r4 = 4'd9;
                -3: canon_r4 = 4'd10;
                -2: canon_r4 = 4'd11;
                -1: canon_r4 = 4'd12;
                 0: canon_r4 = 4'd0;
                 1: canon_r4 = 4'd1;
                 2: canon_r4 = 4'd2;
                 3: canon_r4 = 4'd3;
                 4: canon_r4 = 4'd4;
                 5: canon_r4 = 4'd5;
                 6: canon_r4 = 4'd6;
                default: canon_r4 = norm_mod($signed(x), M4);
            endcase
        end
    endfunction

    function [4:0] canon_r5;
        input signed [W5-1:0] x;
        begin
            case ($signed(x))
                -8: canon_r5 = 5'd9;
                -7: canon_r5 = 5'd10;
                -6: canon_r5 = 5'd11;
                -5: canon_r5 = 5'd12;
                -4: canon_r5 = 5'd13;
                -3: canon_r5 = 5'd14;
                -2: canon_r5 = 5'd15;
                -1: canon_r5 = 5'd16;
                 0: canon_r5 = 5'd0;
                 1: canon_r5 = 5'd1;
                 2: canon_r5 = 5'd2;
                 3: canon_r5 = 5'd3;
                 4: canon_r5 = 5'd4;
                 5: canon_r5 = 5'd5;
                 6: canon_r5 = 5'd6;
                 7: canon_r5 = 5'd7;
                 8: canon_r5 = 5'd8;
                default: canon_r5 = norm_mod($signed(x), M5);
            endcase
        end
    endfunction

    function [3:0] x_mod13_from_centered;
        input signed [OUT_WIDTH-1:0] x;
        integer xs;
        begin
            xs = $signed(x);
            // Compare the centered reconstruction against the redundant channels
            // using the actual signed value. Adding M_BASE here is wrong because
            // 1155 is not congruent to 0 modulo 13, so negative in-range results
            // would be shifted to the wrong redundant residue.
            x_mod13_from_centered = norm_mod(xs, M4);
        end
    endfunction

    function [4:0] x_mod17_from_centered;
        input signed [OUT_WIDTH-1:0] x;
        integer xs;
        begin
            xs = $signed(x);
            // Same centered-value comparison rule for mod-17.
            x_mod17_from_centered = norm_mod(xs, M5);
        end
    endfunction

    // Compute the expected redundant residues from a candidate base residue vector
    // using a tiny mixed-radix forward engine. This stays in residue space and never
    // reconstructs the full X candidate.
    always @* begin
        b0_w = n0_r;
        b1_w = n1_r;
        b2_w = n2_r;
        b3_w = n3_r;

        case (lane_idx_r)
            2'd0: b0_w = cand_val_r[1:0];
            2'd1: b1_w = cand_val_r[2:0];
            2'd2: b2_w = cand_val_r[2:0];
            default: b3_w = cand_val_r[3:0];
        endcase

        begin : predict_reds
            integer x1_i;
            integer t2_i;
            integer x2_i;
            integer t3_i;
            integer x3_i;
            integer t4_i;
            integer x_pos_i;
            integer x_ctr_i;
            x1_i = b0_w;
            t2_i = norm_mod((b1_w - norm_mod(x1_i, M1)), M1);
            t2_i = norm_mod(t2_i * 2, M1);          // inv(3 mod 5) = 2
            x2_i = x1_i + (3 * t2_i);

            t3_i = norm_mod((b2_w - norm_mod(x2_i, M2)), M2);
            x3_i = x2_i + (15 * t3_i);              // inv(15 mod 7) = 1

            t4_i = norm_mod((b3_w - norm_mod(x3_i, M3)), M3);
            t4_i = norm_mod(t4_i * 2, M3);          // inv(105 mod 11) = 2

            x_pos_i = x3_i + (105 * t4_i);
            if (x_pos_i > (M_BASE / 2))
                x_ctr_i = x_pos_i - M_BASE;
            else
                x_ctr_i = x_pos_i;

            exp13_w = norm_mod(x_ctr_i, M4);
            exp17_w = norm_mod(x_ctr_i, M5);
        end

        hit_w = (exp13_w == n4_r) && (exp17_w == n5_r);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            start_d          <= 1'b0;
            Correct_Done     <= 1'b0;
            corr_r0          <= '0;
            corr_r1          <= '0;
            corr_r2          <= '0;
            corr_r3          <= '0;
            Error_Detected   <= 1'b0;
            Corrected        <= 1'b0;
            Valid            <= 1'b0;
            chk13_r          <= 1'b0;
            chk17_r          <= 1'b0;
            lane_idx_r       <= 2'd0;
            cand_val_r       <= 4'd0;
            winner_found_r   <= 1'b0;
            conflict_found_r <= 1'b0;
            winner_lane_r    <= 2'd0;
            winner_res_r     <= 4'd0;
            n0_r             <= '0;
            n1_r             <= '0;
            n2_r             <= '0;
            n3_r             <= '0;
            n4_r             <= '0;
            n5_r             <= '0;
        end else begin
            start_d      <= Correct_Start;
            Correct_Done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        n0_r <= canon_r0(r0);
                        n1_r <= canon_r1(r1);
                        n2_r <= canon_r2(r2);
                        n3_r <= canon_r3(r3);
                        n4_r <= canon_r4(r4);
                        n5_r <= canon_r5(r5);

                        corr_r0 <= r0;
                        corr_r1 <= r1;
                        corr_r2 <= r2;
                        corr_r3 <= r3;

                        winner_found_r   <= 1'b0;
                        conflict_found_r <= 1'b0;
                        winner_lane_r    <= 2'd0;
                        winner_res_r     <= 4'd0;
                        lane_idx_r       <= 2'd0;
                        cand_val_r       <= 4'd0;
                        state            <= S_PREP;
                    end
                end

                S_PREP: begin
                    chk13_r <= (x_mod13_from_centered(X_base) == n4_r);
                    chk17_r <= (x_mod17_from_centered(X_base) == n5_r);

                    if ((x_mod13_from_centered(X_base) == n4_r) && (x_mod17_from_centered(X_base) == n5_r)) begin
                        corr_r0        <= r0;
                        corr_r1        <= r1;
                        corr_r2        <= r2;
                        corr_r3        <= r3;
                        Error_Detected <= 1'b0;
                        Corrected      <= 1'b0;
                        Valid          <= 1'b1;
                        state          <= S_DONE;
                    end else if ((x_mod13_from_centered(X_base) == n4_r) ^ (x_mod17_from_centered(X_base) == n5_r)) begin
                        corr_r0        <= r0;
                        corr_r1        <= r1;
                        corr_r2        <= r2;
                        corr_r3        <= r3;
                        Error_Detected <= 1'b1;
                        Corrected      <= 1'b1;
                        Valid          <= 1'b1;
                        state          <= S_DONE;
                    end else begin
                        Error_Detected   <= 1'b1;
                        Corrected        <= 1'b0;
                        Valid            <= 1'b0;
                        winner_found_r   <= 1'b0;
                        conflict_found_r <= 1'b0;
                        winner_lane_r    <= 2'd0;
                        winner_res_r     <= 4'd0;
                        lane_idx_r       <= 2'd0;
                        cand_val_r       <= 4'd0;
                        state            <= S_EVAL;
                    end
                end

                S_EVAL: begin
                    if (hit_w) begin
                        if (!winner_found_r) begin
                            winner_found_r <= 1'b1;
                            winner_lane_r  <= lane_idx_r;
                            winner_res_r   <= cand_val_r;
                        end else if ((winner_lane_r != lane_idx_r) || (winner_res_r != cand_val_r)) begin
                            conflict_found_r <= 1'b1;
                        end
                    end

                    if (conflict_found_r || ((winner_found_r && hit_w) && ((winner_lane_r != lane_idx_r) || (winner_res_r != cand_val_r)))) begin
                        state <= S_RESOLVE;
                    end else begin
                        case (lane_idx_r)
                            2'd0: begin
                                if (cand_val_r == 4'd2) begin
                                    lane_idx_r <= 2'd1;
                                    cand_val_r <= 4'd0;
                                end else begin
                                    cand_val_r <= cand_val_r + 4'd1;
                                end
                            end
                            2'd1: begin
                                if (cand_val_r == 4'd4) begin
                                    lane_idx_r <= 2'd2;
                                    cand_val_r <= 4'd0;
                                end else begin
                                    cand_val_r <= cand_val_r + 4'd1;
                                end
                            end
                            2'd2: begin
                                if (cand_val_r == 4'd6) begin
                                    lane_idx_r <= 2'd3;
                                    cand_val_r <= 4'd0;
                                end else begin
                                    cand_val_r <= cand_val_r + 4'd1;
                                end
                            end
                            default: begin
                                if (cand_val_r == 4'd10)
                                    state <= S_RESOLVE;
                                else
                                    cand_val_r <= cand_val_r + 4'd1;
                            end
                        endcase
                    end
                end

                S_RESOLVE: begin
                    corr_r0 <= r0;
                    corr_r1 <= r1;
                    corr_r2 <= r2;
                    corr_r3 <= r3;

                    if (!winner_found_r || conflict_found_r) begin
                        Error_Detected <= 1'b1;
                        Corrected      <= 1'b0;
                        Valid          <= 1'b0;
                    end else begin
                        Error_Detected <= 1'b1;
                        Corrected      <= 1'b1;
                        Valid          <= 1'b1;
                        case (winner_lane_r)
                            2'd0: corr_r0 <= center_with_modulus(winner_res_r, M0);
                            2'd1: corr_r1 <= center_with_modulus(winner_res_r, M1);
                            2'd2: corr_r2 <= center_with_modulus(winner_res_r, M2);
                            default: corr_r3 <= center_with_modulus(winner_res_r, M3);
                        endcase
                    end
                    state <= S_DONE;
                end

                S_DONE: begin
                    Correct_Done <= 1'b1;
                    state        <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

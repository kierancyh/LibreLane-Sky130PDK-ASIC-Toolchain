`timescale 1ns/1ps

module rns_mrc_recon #(
    parameter W0        = 2,
    parameter W1        = 3,
    parameter W2        = 3,
    parameter W3        = 4,
    parameter OUT_WIDTH = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 MRC_Start,
    input  wire [W0-1:0]        r0,
    input  wire [W1-1:0]        r1,
    input  wire [W2-1:0]        r2,
    input  wire [W3-1:0]        r3,
    output reg  [OUT_WIDTH-1:0] X_out,
    output reg                  MRC_Done
);

    localparam integer MOD0      = 3;
    localparam integer MOD1      = 5;
    localparam integer MOD2      = 7;
    localparam integer MOD3      = 11;

    localparam integer MPREV1    = 3;
    localparam integer MPREV2    = 15;
    localparam integer MPREV3    = 105;
    localparam integer M_TOTAL   = 1155;

    localparam integer INV_12    = 2; // inv(3 mod 5)
    localparam integer INV_123   = 1; // inv(15 mod 7)
    localparam integer INV_1234  = 2; // inv(105 mod 11)

    localparam [2:0]
        S_IDLE = 3'd0,
        S_S1   = 3'd1,
        S_S2   = 3'd2,
        S_S3   = 3'd3,
        S_S4   = 3'd4,
        S_DONE = 3'd5;

    reg [2:0] state;

    reg start_d;
    wire start_pulse = MRC_Start & ~start_d;

    reg [1:0] r0_mod_r;
    reg [2:0] r1_mod_r;
    reg [2:0] r2_mod_r;
    reg [3:0] r3_mod_r;

    reg [1:0] X1_r;   // 0..2
    reg [3:0] X2_r;   // 0..14
    reg [6:0] X3_r;   // 0..104

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

    wire [2:0]  t2_w;
    wire [3:0]  X2_next_w;
    wire [2:0]  t3_w;
    wire [6:0]  X3_next_w;
    wire [3:0]  t4_w;
    wire [10:0] X4_w;
    wire [10:0] total_mod_w;

    assign t2_w        = norm_mod(norm_mod(r1_mod_r - norm_mod(X1_r, MOD1), MOD1) * INV_12, MOD1);
    assign X2_next_w   = X1_r + (t2_w * MPREV1);

    assign t3_w        = norm_mod(norm_mod(r2_mod_r - norm_mod(X2_r, MOD2), MOD2) * INV_123, MOD2);
    assign X3_next_w   = X2_r + (t3_w * MPREV2);

    assign t4_w        = norm_mod(norm_mod(r3_mod_r - norm_mod(X3_r, MOD3), MOD3) * INV_1234, MOD3);
    assign X4_w        = X3_r + (t4_w * MPREV3);

    assign total_mod_w = norm_mod(X4_w, M_TOTAL);

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            start_d  <= 1'b0;
            MRC_Done <= 1'b0;
        end else begin
            start_d  <= MRC_Start;
            MRC_Done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        r0_mod_r <= norm_mod(r0, MOD0);
                        r1_mod_r <= norm_mod(r1, MOD1);
                        r2_mod_r <= norm_mod(r2, MOD2);
                        r3_mod_r <= norm_mod(r3, MOD3);
                        state    <= S_S1;
                    end
                end

                S_S1: begin
                    X1_r  <= r0_mod_r;
                    state <= S_S2;
                end

                S_S2: begin
                    X2_r  <= X2_next_w;
                    state <= S_S3;
                end

                S_S3: begin
                    X3_r  <= X3_next_w;
                    state <= S_S4;
                end

                S_S4: begin
                    X_out <= total_mod_w;
                    state <= S_DONE;
                end

                S_DONE: begin
                    MRC_Done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
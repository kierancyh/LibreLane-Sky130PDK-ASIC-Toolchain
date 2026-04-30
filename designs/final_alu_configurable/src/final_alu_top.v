`timescale 1ns/1ps
`include "final_alu_cfg.svh"
module final_alu_top #(
    parameter WIDTH_IN  = 16,
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
    parameter CRNS_EN         = 1,
    parameter CENTERED_OUT_EN = 1
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        Start,
    input  wire [1:0]                  Op_Sel,
    input  wire signed [WIDTH_IN-1:0]  A_in,
    input  wire signed [WIDTH_IN-1:0]  B_in,
    output wire                        Done,
    output wire signed [WIDTH_IN-1:0]  X_out,
    output wire                        Error_Detected,
    output wire                        Corrected,
    output wire                        Valid
);

    wire Load_IN, Encode_EN, ALU_EN, Recon_Start, Correct_Start, Out_EN;
    wire Encode_Done_all, ALU_Done_all, Recon_Done, Correct_Done;
    wire [3:0] CU_state_dbg;

    // Single-source local aliases used only inside the datapath.
    wire load_in_local   = Load_IN;
    wire encode_en_local = Encode_EN;
    wire alu_en_local    = ALU_EN;
    wire out_en_local    = Out_EN;

    reg signed [WIDTH_IN-1:0] A_req, B_req;
    reg [1:0]                 OpSel_req;
    reg signed [WIDTH_IN-1:0] A_reg, B_reg;
    reg [1:0]                 OpSel_reg;

    // Narrow residue views used by the slice/corrector blocks.
    wire signed [W0-1:0] a_r0, b_r0;
    wire signed [W1-1:0] a_r1, b_r1;
    wire signed [W2-1:0] a_r2, b_r2;
    wire signed [W3-1:0] a_r3, b_r3;
    wire signed [W4-1:0] a_r4, b_r4;
    wire signed [W5-1:0] a_r5, b_r5;

    // Full-width residue views used by the encoder/recon blocks.
    wire signed [`FINAL_ALU_RES_W-1:0] a_r0_full, b_r0_full;
    wire signed [`FINAL_ALU_RES_W-1:0] a_r1_full, b_r1_full;
    wire signed [`FINAL_ALU_RES_W-1:0] a_r2_full, b_r2_full;
    wire signed [`FINAL_ALU_RES_W-1:0] a_r3_full, b_r3_full;
    wire signed [`FINAL_ALU_RES_W-1:0] a_r4_full, b_r4_full;
    wire signed [`FINAL_ALU_RES_W-1:0] a_r5_full, b_r5_full;

    wire signed [W0-1:0] z_r0;
    wire signed [W1-1:0] z_r1;
    wire signed [W2-1:0] z_r2;
    wire signed [W3-1:0] z_r3;
    wire signed [W4-1:0] z_r4;
    wire signed [W5-1:0] z_r5;

    wire signed [W0-1:0] corr_r0;
    wire signed [W1-1:0] corr_r1;
    wire signed [W2-1:0] corr_r2;
    wire signed [W3-1:0] corr_r3;

    wire signed [`FINAL_ALU_RES_W-1:0] z_r0_full = {{(`FINAL_ALU_RES_W-W0){z_r0[W0-1]}}, z_r0};
    wire signed [`FINAL_ALU_RES_W-1:0] z_r1_full = {{(`FINAL_ALU_RES_W-W1){z_r1[W1-1]}}, z_r1};
    wire signed [`FINAL_ALU_RES_W-1:0] z_r2_full = {{(`FINAL_ALU_RES_W-W2){z_r2[W2-1]}}, z_r2};
    wire signed [`FINAL_ALU_RES_W-1:0] z_r3_full = {{(`FINAL_ALU_RES_W-W3){z_r3[W3-1]}}, z_r3};
    wire signed [`FINAL_ALU_RES_W-1:0] corr_r0_full = {{(`FINAL_ALU_RES_W-W0){corr_r0[W0-1]}}, corr_r0};
    wire signed [`FINAL_ALU_RES_W-1:0] corr_r1_full = {{(`FINAL_ALU_RES_W-W1){corr_r1[W1-1]}}, corr_r1};
    wire signed [`FINAL_ALU_RES_W-1:0] corr_r2_full = {{(`FINAL_ALU_RES_W-W2){corr_r2[W2-1]}}, corr_r2};
    wire signed [`FINAL_ALU_RES_W-1:0] corr_r3_full = {{(`FINAL_ALU_RES_W-W3){corr_r3[W3-1]}}, corr_r3};

    wire Encode_Done_A, Encode_Done_B;
    wire slice0_done, slice1_done, slice2_done, slice3_done, slice4_done, slice5_done;
    wire                 Error_now;
    wire                 Corrected_now;
    wire                 Valid_now;
    wire signed [WIDTH_IN-1:0] X_base_pre;
    wire signed [WIDTH_IN-1:0] X_final_post;
    wire recon_post_sel = (CU_state_dbg == 4'd6);

    assign a_r0 = a_r0_full[W0-1:0];
    assign a_r1 = a_r1_full[W1-1:0];
    assign a_r2 = a_r2_full[W2-1:0];
    assign a_r3 = a_r3_full[W3-1:0];
    assign a_r4 = a_r4_full[W4-1:0];
    assign a_r5 = a_r5_full[W5-1:0];

    assign b_r0 = b_r0_full[W0-1:0];
    assign b_r1 = b_r1_full[W1-1:0];
    assign b_r2 = b_r2_full[W2-1:0];
    assign b_r3 = b_r3_full[W3-1:0];
    assign b_r4 = b_r4_full[W4-1:0];
    assign b_r5 = b_r5_full[W5-1:0];

    always @(posedge clk) begin
        A_req     <= A_in;
        B_req     <= B_in;
        OpSel_req <= Op_Sel;
    end

    always @(posedge clk) begin
        if (load_in_local) begin
            A_reg     <= A_req;
            B_reg     <= B_req;
            OpSel_reg <= OpSel_req;
        end
    end

    final_alu_cu u_cu (
        .clk         (clk),
        .rst_n       (rst_n),
        .Start       (Start),
        .Done        (Done),
        .CU_state_dbg(CU_state_dbg),
        .Encode_Done (Encode_Done_all),
        .ALU_Done    (ALU_Done_all),
        .Recon_Done  (Recon_Done),
        .Correct_Done(Correct_Done),
        .Load_IN     (Load_IN),
        .Encode_EN   (Encode_EN),
        .ALU_EN      (ALU_EN),
        .Recon_Start (Recon_Start),
        .Correct_Start(Correct_Start),
        .Out_EN      (Out_EN)
    );

    final_alu_encoder #(
        .WIDTH_IN (WIDTH_IN), .M0(M0), .M1(M1), .M2(M2), .M3(M3), .M4(M4), .M5(M5),
        .CRNS_EN(CRNS_EN)
    ) u_enc_a (
        .clk(clk), .rst_n(rst_n), .Encode_EN(encode_en_local), .x(A_reg),
        .Encode_Done(Encode_Done_A),
        .base_r0(a_r0_full), .base_r1(a_r1_full), .base_r2(a_r2_full), .base_r3(a_r3_full), .red_r0(a_r4_full), .red_r1(a_r5_full)
    );

    final_alu_encoder #(
        .WIDTH_IN (WIDTH_IN), .M0(M0), .M1(M1), .M2(M2), .M3(M3), .M4(M4), .M5(M5),
        .CRNS_EN(CRNS_EN)
    ) u_enc_b (
        .clk(clk), .rst_n(rst_n), .Encode_EN(encode_en_local), .x(B_reg),
        .Encode_Done(Encode_Done_B),
        .base_r0(b_r0_full), .base_r1(b_r1_full), .base_r2(b_r2_full), .base_r3(b_r3_full), .red_r0(b_r4_full), .red_r1(b_r5_full)
    );

    assign Encode_Done_all = Encode_Done_A & Encode_Done_B;

    final_alu_slice #(.MODULUS(M0), .WIDTH(W0), .CRNS_EN(CRNS_EN)) u_slice0 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(alu_en_local), .op_sel(OpSel_reg), .a(a_r0), .b(b_r0), .y(z_r0), .ALU_Done(slice0_done)
    );
    final_alu_slice #(.MODULUS(M1), .WIDTH(W1), .CRNS_EN(CRNS_EN)) u_slice1 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(alu_en_local), .op_sel(OpSel_reg), .a(a_r1), .b(b_r1), .y(z_r1), .ALU_Done(slice1_done)
    );
    final_alu_slice #(.MODULUS(M2), .WIDTH(W2), .CRNS_EN(CRNS_EN)) u_slice2 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(alu_en_local), .op_sel(OpSel_reg), .a(a_r2), .b(b_r2), .y(z_r2), .ALU_Done(slice2_done)
    );
    final_alu_slice #(.MODULUS(M3), .WIDTH(W3), .CRNS_EN(CRNS_EN)) u_slice3 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(alu_en_local), .op_sel(OpSel_reg), .a(a_r3), .b(b_r3), .y(z_r3), .ALU_Done(slice3_done)
    );
    final_alu_slice #(.MODULUS(M4), .WIDTH(W4), .CRNS_EN(CRNS_EN)) u_slice4 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(alu_en_local), .op_sel(OpSel_reg), .a(a_r4), .b(b_r4), .y(z_r4), .ALU_Done(slice4_done)
    );
    final_alu_slice #(.MODULUS(M5), .WIDTH(W5), .CRNS_EN(CRNS_EN)) u_slice5 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(alu_en_local), .op_sel(OpSel_reg), .a(a_r5), .b(b_r5), .y(z_r5), .ALU_Done(slice5_done)
    );

    assign ALU_Done_all = slice0_done & slice1_done & slice2_done & slice3_done & slice4_done & slice5_done;

    final_alu_recon #(
        .OUT_WIDTH(WIDTH_IN)
    ) u_recon (
        .clk(clk),
        .rst_n(rst_n),
        .Recon_Start(Recon_Start),
        .base_r0(recon_post_sel ? corr_r0_full : z_r0_full),
        .base_r1(recon_post_sel ? corr_r1_full : z_r1_full),
        .base_r2(recon_post_sel ? corr_r2_full : z_r2_full),
        .base_r3(recon_post_sel ? corr_r3_full : z_r3_full),
        .X_out(X_final_post),
        .Recon_Done(Recon_Done)
    );

    assign X_base_pre = X_final_post;

    final_alu_corrector #(
        .W0(W0), .W1(W1), .W2(W2), .W3(W3), .W4(W4), .W5(W5), .OUT_WIDTH(WIDTH_IN)
    ) u_corrector (
        .clk(clk),
        .rst_n(rst_n),
        .Correct_Start(Correct_Start),
        .X_base(X_base_pre),
        .r0(z_r0), .r1(z_r1), .r2(z_r2), .r3(z_r3), .r4(z_r4), .r5(z_r5),
        .corr_r0(corr_r0), .corr_r1(corr_r1), .corr_r2(corr_r2), .corr_r3(corr_r3),
        .Error_Detected(Error_now),
        .Corrected(Corrected_now),
        .Valid(Valid_now),
        .Correct_Done(Correct_Done)
    );

    reg signed [WIDTH_IN-1:0] X_reg;
    reg                       Error_reg;
    reg                       Corrected_reg;
    reg                       Valid_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            X_reg         <= '0;
            Error_reg     <= 1'b0;
            Corrected_reg <= 1'b0;
            Valid_reg     <= 1'b0;
        end else if (out_en_local) begin
            X_reg         <= X_final_post;
            Error_reg     <= Error_now;
            Corrected_reg <= Corrected_now;
            Valid_reg     <= Valid_now;
        end
    end

    assign X_out          = X_reg;
    assign Error_Detected = Error_reg;
    assign Corrected      = Corrected_reg;
    assign Valid          = Valid_reg;

endmodule

`timescale 1ns/1ps
module crns_top_crt #(
    parameter WIDTH_IN  = 16,
    parameter M0 = 3,
    parameter M1 = 5,
    parameter M2 = 7,
    parameter M3 = 11,
    parameter W0 = 2,
    parameter W1 = 3,
    parameter W2 = 3,
    parameter W3 = 4,
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
    output wire signed [WIDTH_IN-1:0]  X_out
);

    // Control wires
    wire Load_IN;
    wire Encode_EN;
    wire ALU_EN;
    wire CRT_Start;
    wire MRC_Start;   // unused, kept for CU port compatibility
    wire Out_EN;

    wire Encode_Done_all;
    wire ALU_Done_all;
    wire CRT_Done;
    wire MRC_Done;
    assign MRC_Done = 1'b0;

    wire [2:0] CU_state_dbg;

    // ------------------------------------------------------------------
    // Input hardening
    // ------------------------------------------------------------------
    // Problem observed in signoff-failing dedicated CRT runs:
    // direct external-input -> Load_IN mux -> active register paths create
    // long antenna-sensitive nets, especially on Op_Sel[0] and some B_in bits.
    //
    // To harden this, always sample external inputs into a small shadow bank.
    // Then Load_IN copies only local registered values into the active datapath
    // registers. This keeps the external pins off the Load_IN-controlled muxes.
    // ------------------------------------------------------------------
    reg signed [WIDTH_IN-1:0] A_req, B_req;
    reg [1:0]                 OpSel_req;

    reg signed [WIDTH_IN-1:0] A_reg, B_reg;
    reg [1:0]                 OpSel_reg;

    // Shadow bank: samples external inputs every cycle.
    always @(posedge clk) begin
        A_req     <= A_in;
        B_req     <= B_in;
        OpSel_req <= Op_Sel;
    end

    // Active bank: loaded only when the CU asserts Load_IN.
    always @(posedge clk) begin
        if (Load_IN) begin
            A_reg     <= A_req;
            B_reg     <= B_req;
            OpSel_reg <= OpSel_req;
        end
    end

    crns_cu u_cu (
        .clk         (clk),
        .rst_n       (rst_n),
        .Start       (Start),
        .Recon_Mode  (1'b0),
        .Done        (Done),
        .CU_state_dbg(CU_state_dbg),
        .Encode_Done (Encode_Done_all),
        .ALU_Done    (ALU_Done_all),
        .CRT_Done    (CRT_Done),
        .MRC_Done    (MRC_Done),
        .Load_IN     (Load_IN),
        .Encode_EN   (Encode_EN),
        .ALU_EN      (ALU_EN),
        .CRT_Start   (CRT_Start),
        .MRC_Start   (MRC_Start),
        .Out_EN      (Out_EN)
    );

    // Encoders: A_reg and B_reg -> centered residues
    wire signed [W0-1:0] a_r0;
    wire signed [W1-1:0] a_r1;
    wire signed [W2-1:0] a_r2;
    wire signed [W3-1:0] a_r3;
    wire                 Encode_Done_A;

    wire signed [W0-1:0] b_r0;
    wire signed [W1-1:0] b_r1;
    wire signed [W2-1:0] b_r2;
    wire signed [W3-1:0] b_r3;
    wire                 Encode_Done_B;

    crns_encoder #(
        .WIDTH_IN (WIDTH_IN),
        .M0       (M0),
        .M1       (M1),
        .M2       (M2),
        .M3       (M3),
        .W0       (W0),
        .W1       (W1),
        .W2       (W2),
        .W3       (W3),
        .CRNS_EN  (CRNS_EN)
    ) u_enc_a (
        .clk        (clk),
        .rst_n      (rst_n),
        .Encode_EN  (Encode_EN),
        .x          (A_reg),
        .Encode_Done(Encode_Done_A),
        .r0         (a_r0),
        .r1         (a_r1),
        .r2         (a_r2),
        .r3         (a_r3)
    );

    crns_encoder #(
        .WIDTH_IN (WIDTH_IN),
        .M0       (M0),
        .M1       (M1),
        .M2       (M2),
        .M3       (M3),
        .W0       (W0),
        .W1       (W1),
        .W2       (W2),
        .W3       (W3),
        .CRNS_EN  (CRNS_EN)
    ) u_enc_b (
        .clk        (clk),
        .rst_n      (rst_n),
        .Encode_EN  (Encode_EN),
        .x          (B_reg),
        .Encode_Done(Encode_Done_B),
        .r0         (b_r0),
        .r1         (b_r1),
        .r2         (b_r2),
        .r3         (b_r3)
    );

    assign Encode_Done_all = Encode_Done_A & Encode_Done_B;

    // Modular ALU slices
    wire signed [W0-1:0] z_r0;
    wire signed [W1-1:0] z_r1;
    wire signed [W2-1:0] z_r2;
    wire signed [W3-1:0] z_r3;

    wire slice0_done;
    wire slice1_done;
    wire slice2_done;
    wire slice3_done;

    crns_slice #(.MODULUS(M0), .WIDTH(W0), .CRNS_EN(CRNS_EN)) u_slice0 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(ALU_EN), .op_sel(OpSel_reg), .a(a_r0), .b(b_r0), .y(z_r0), .ALU_Done(slice0_done)
    );
    crns_slice #(.MODULUS(M1), .WIDTH(W1), .CRNS_EN(CRNS_EN)) u_slice1 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(ALU_EN), .op_sel(OpSel_reg), .a(a_r1), .b(b_r1), .y(z_r1), .ALU_Done(slice1_done)
    );
    crns_slice #(.MODULUS(M2), .WIDTH(W2), .CRNS_EN(CRNS_EN)) u_slice2 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(ALU_EN), .op_sel(OpSel_reg), .a(a_r2), .b(b_r2), .y(z_r2), .ALU_Done(slice2_done)
    );
    crns_slice #(.MODULUS(M3), .WIDTH(W3), .CRNS_EN(CRNS_EN)) u_slice3 (
        .clk(clk), .rst_n(rst_n), .ALU_EN(ALU_EN), .op_sel(OpSel_reg), .a(a_r3), .b(b_r3), .y(z_r3), .ALU_Done(slice3_done)
    );

    assign ALU_Done_all = slice0_done & slice1_done & slice2_done & slice3_done;

    // CRT reconstruction only
    wire signed [WIDTH_IN-1:0] X_crt;

    crns_crt_recon #(
        .W0        (W0),
        .W1        (W1),
        .W2        (W2),
        .W3        (W3),
        .OUT_WIDTH (WIDTH_IN)
    ) u_crt (
        .clk       (clk),
        .rst_n     (rst_n),
        .CRT_Start (CRT_Start),
        .r0        (z_r0),
        .r1        (z_r1),
        .r2        (z_r2),
        .r3        (z_r3),
        .X_out     (X_crt),
        .CRT_Done  (CRT_Done)
    );

    reg signed [WIDTH_IN-1:0] X_reg;

    always @(posedge clk) begin
        if (Out_EN)
            X_reg <= X_crt;
    end

    assign X_out = X_reg;

endmodule

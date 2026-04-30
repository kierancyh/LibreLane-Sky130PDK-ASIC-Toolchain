`timescale 1ns/1ps

// Function: Forward Conversion (Binary → Residues)
// Hardware counterpart of Python encode(): encode(x, [3, 5, 7, 11])

// Data Path: Stage 2 – Encoder Bank
// Control:
//   - CU asserts Encode_EN
//   - Encoder outputs Encode_Done high for 1 cycle
// Moduli Set: M0 = 3, M1 = 5, M2 = 7, M3 = 11

// Notes:
//   - Unsigned domain only (x ≥ 0).
//   - One-cycle latency.
//   - Modulus operations are constant-mod (synthesizable)
//   - Reset is kept on handshake only; residue outputs are not reset

module rns_encoder #(
    parameter WIDTH_IN = 16,
    parameter M0 = 3,
    parameter M1 = 5,
    parameter M2 = 7,
    parameter M3 = 11,
    parameter W0 = 2,
    parameter W1 = 3,
    parameter W2 = 3,
    parameter W3 = 4
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 Encode_EN,
    input  wire [WIDTH_IN-1:0]  x,
    output reg                  Encode_Done,
    output reg [W0-1:0]         r0,
    output reg [W1-1:0]         r1,
    output reg [W2-1:0]         r2,
    output reg [W3-1:0]         r3
);

    wire [W0-1:0] r0_next;
    wire [W1-1:0] r1_next;
    wire [W2-1:0] r2_next;
    wire [W3-1:0] r3_next;

    assign r0_next = x % M0;
    assign r1_next = x % M1;
    assign r2_next = x % M2;
    assign r3_next = x % M3;

    always @(posedge clk) begin
        if (!rst_n) begin
            Encode_Done <= 1'b0;
        end else begin
            Encode_Done <= 1'b0;

            if (Encode_EN) begin
                r0 <= r0_next;
                r1 <= r1_next;
                r2 <= r2_next;
                r3 <= r3_next;
                Encode_Done <= 1'b1;
            end
        end
    end

endmodule

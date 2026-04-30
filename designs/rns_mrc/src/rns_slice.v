`timescale 1ns/1ps

// Function: Per-Modulus RNS ALU Slice (ADD / SUB / MUL)
// Hardware counterpart of Python per-channel ops in ops.py:
//   add(a, b, m) = (a + b) % m
//   sub(a, b, m) = (a - b) % m
//   mul(a, b, m) = (a * b) % m

// Data Path: Stage 3 – Modular ALUs
// Control:
//   - CU asserts ALU_EN (start operation for the specific slice)
//   - Slice asserts ALU_Done HIGH exactly one cycle later (Handshake)

// Operation Select (op_sel):
//   2'b00 : ADD
//   2'b01 : SUB
//   2'b10 : MUL
//   others: result = 0

module rns_slice #(
    parameter MODULUS = 3,
    parameter WIDTH   = 2
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 ALU_EN,
    input  wire [1:0]           op_sel,
    input  wire [WIDTH-1:0]     a,
    input  wire [WIDTH-1:0]     b,
    output reg  [WIDTH-1:0]     y,
    output reg                  ALU_Done
);

    reg [WIDTH-1:0] y_next;
    reg             start_d;
    integer         tmp;

    always @* begin
        y_next = {WIDTH{1'b0}};
        tmp    = 0;

        case (op_sel)
            2'b00: begin
                tmp    = a + b;
                tmp    = tmp % MODULUS;
                y_next = tmp[WIDTH-1:0];
            end

            2'b01: begin
                tmp    = a + MODULUS - b;
                tmp    = tmp % MODULUS;
                y_next = tmp[WIDTH-1:0];
            end

            2'b10: begin
                tmp    = a * b;
                tmp    = tmp % MODULUS;
                y_next = tmp[WIDTH-1:0];
            end

            default: begin
                y_next = {WIDTH{1'b0}};
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            start_d  <= 1'b0;
            ALU_Done <= 1'b0;
        end else begin
            ALU_Done <= start_d;
            start_d  <= ALU_EN;

            if (ALU_EN)
                y <= y_next;
        end
    end

endmodule

`timescale 1ns/1ps
module crns_slice #(
    parameter MODULUS = 3,
    parameter WIDTH   = 2,
    parameter CRNS_EN = 1
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    ALU_EN,
    input  wire [1:0]              op_sel,

    // Signed centered residues when CRNS_EN=1
    input  wire signed [WIDTH-1:0] a,
    input  wire signed [WIDTH-1:0] b,

    output reg  signed [WIDTH-1:0] y,
    output reg                     ALU_Done
);

    reg signed [WIDTH-1:0] y_next;
    reg                    start_d;

    integer raw;
    integer tmp;

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

    always @* begin
        raw    = 0;
        tmp    = 0;
        y_next = '0;

        case (op_sel)
            2'b00: raw = a + b;   // ADD
            2'b01: raw = a - b;   // SUB
            2'b10: raw = a * b;   // MUL
            default: raw = 0;
        endcase

        tmp = CRNS_EN ? norm_bal(raw, MODULUS) : norm_std(raw, MODULUS);
        y_next = tmp[WIDTH-1:0];
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
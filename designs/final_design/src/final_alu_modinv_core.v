`timescale 1ns/1ps
module final_alu_modinv_core #(
    parameter integer WM = 5
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,
    input  wire [WM-1:0]   a_in,
    input  wire [WM-1:0]   m_in,
    output reg             done,
    output reg             valid,
    output reg [WM-1:0]    inv_out
);
    reg running;
    reg [WM-1:0] a_reg;
    reg [WM-1:0] m_reg;
    reg [WM-1:0] cand_reg;
    integer aa_i;
    integer mm_i;
    integer cc_i;
    integer prod_i;

    always @(posedge clk) begin
        if (!rst_n) begin
            running <= 1'b0;
            done    <= 1'b0;
            valid   <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !running) begin
                aa_i = a_in;
                mm_i = m_in;
                if (mm_i > 1) begin
                    aa_i = aa_i % mm_i;
                    if (aa_i < 0)
                        aa_i = aa_i + mm_i;
                end else begin
                    aa_i = 0;
                end
                a_reg    <= aa_i[WM-1:0];
                m_reg    <= m_in;
                cand_reg <= {{(WM-1){1'b0}},1'b1};
                inv_out  <= {WM{1'b0}};
                valid    <= 1'b0;
                running  <= 1'b1;
            end else if (running) begin
                mm_i = m_reg;
                aa_i = a_reg;
                cc_i = cand_reg;
                if (mm_i <= 1) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                    valid   <= 1'b0;
                    inv_out <= {WM{1'b0}};
                end else begin
                    prod_i = (aa_i * cc_i) % mm_i;
                    if (prod_i == 1) begin
                        running <= 1'b0;
                        done    <= 1'b1;
                        valid   <= 1'b1;
                        inv_out <= cand_reg;
                    end else if (cand_reg >= (m_reg - 1'b1)) begin
                        running <= 1'b0;
                        done    <= 1'b1;
                        valid   <= 1'b0;
                        inv_out <= {WM{1'b0}};
                    end else begin
                        cand_reg <= cand_reg + {{(WM-1){1'b0}},1'b1};
                    end
                end
            end
        end
    end
endmodule

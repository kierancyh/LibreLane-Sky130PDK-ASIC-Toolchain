`timescale 1ns/1ps
module final_alu_cfg_precompute #(
    parameter integer WM = 5,
    parameter integer PW = 20
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [WM-1:0]        m0,
    input  wire [WM-1:0]        m1,
    input  wire [WM-1:0]        m2,
    input  wire [WM-1:0]        m3,
    input  wire [WM-1:0]        m4,
    input  wire [WM-1:0]        m5,
    input  wire [PW-1:0]        M_base,
    output reg                  done,
    output reg                  precomp_ok,
    output reg  [14:0]          usable_subset_bitmap
);

    // The current runtime corrector scans base candidates directly and no longer
    // consumes per-subset reconstruction metadata. Keep precompute intentionally
    // tiny and return the legacy all-usable bitmap for wrapper compatibility.
    always @(posedge clk) begin
        if (!rst_n) begin
            done       <= 1'b0;
            precomp_ok <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                usable_subset_bitmap <= 15'h7fff;
                precomp_ok           <= 1'b1;
                done                 <= 1'b1;
            end
        end
    end

endmodule

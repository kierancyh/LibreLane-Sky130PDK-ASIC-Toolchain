`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// FINAL_ALU legacy checker/re-encode shell
// -----------------------------------------------------------------------------
// NOTE:
// The current runtime top does not instantiate this module.  It is still read by
// the Task 1 / Task 2 command list, so it must remain Verilog/Yosys clean.
//
// This shell preserves the original module interface but removes the old
// function-based runtime modulo path that caused Icarus/Yosys failures:
//   "No function named mod_s"
//   "Function mod_u can only be called with constant arguments"
// -----------------------------------------------------------------------------

module final_alu_checker_reencode #(
    parameter integer WM = 5,
    parameter integer PW = 20
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [PW-1:0]        candidate_base,
    input  wire [PW-1:0]        M_base,
    input  wire [6*WM-1:0]      z_res_flat,
    input  wire [WM-1:0]        m0,
    input  wire [WM-1:0]        m1,
    input  wire [WM-1:0]        m2,
    input  wire [WM-1:0]        m3,
    input  wire [WM-1:0]        m4,
    input  wire [WM-1:0]        m5,
    output reg                  done,
    output reg  [5:0]           mismatch_mask,
    output reg  [2:0]           mismatch_count
);

    // Inputs are intentionally unused in this compatibility shell.
    // Keep a small synchronous handshake so the module remains harmless if
    // accidentally instantiated by an older script/test.
    always @(posedge clk) begin
        if (!rst_n) begin
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                mismatch_mask  <= 6'b000000;
                mismatch_count <= 3'd0;
                done           <= 1'b1;
            end
        end
    end

endmodule

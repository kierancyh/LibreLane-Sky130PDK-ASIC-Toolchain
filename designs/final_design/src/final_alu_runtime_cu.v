`timescale 1ns/1ps
module final_alu_runtime_cu #(
    parameter integer CFG_W = 3,
    parameter integer OP_W  = 4
)(
    input  wire [CFG_W-1:0] cfg_state_in,
    input  wire [OP_W-1:0]  op_state_in,
    output wire [CFG_W-1:0] cfg_state_dbg,
    output wire [OP_W-1:0]  op_state_dbg
);
    assign cfg_state_dbg = cfg_state_in;
    assign op_state_dbg  = op_state_in;
endmodule

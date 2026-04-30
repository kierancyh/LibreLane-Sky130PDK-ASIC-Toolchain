`ifndef FINAL_ALU_CFG_SVH
`define FINAL_ALU_CFG_SVH

// Stage 1 configuration scaffold.
// Structural genericity begins here, while the proven arithmetic remains fixed
// to the current passing CRT baseline.

`define FINAL_ALU_DATA_W        16
`define FINAL_ALU_N_BASE        4
`define FINAL_ALU_N_RED         2
`define FINAL_ALU_N_TOTAL       6
`define FINAL_ALU_RES_W         5

`define FINAL_ALU_BASE_MOD_0      3
`define FINAL_ALU_BASE_MOD_1      5
`define FINAL_ALU_BASE_MOD_2      7
`define FINAL_ALU_BASE_MOD_3      11
`define FINAL_ALU_RED_MOD_0       13
`define FINAL_ALU_RED_MOD_1       17

`define FINAL_ALU_M_BASE        1155
`define FINAL_ALU_CENTER_HALF   577

`define FINAL_ALU_FAULT_NONE    0
`define FINAL_ALU_FAULT_BASE    1
`define FINAL_ALU_FAULT_RED     2

`endif

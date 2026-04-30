`timescale 1ns/1ps
// V50B: conservative combinational range/centering stage.
// The top-level captures corrector outputs before this stage, but the module
// interface stays compatible with the original working design.
module final_alu_range_check #(
    parameter integer XW = 24,
    parameter integer PW = 20
)(
    input  wire                     raw_range_error,
    input  wire [PW-1:0]            M_base,
    input  wire [PW-1:0]            half_range,
    input  wire [PW-1:0]            candidate_base,
    output reg                      range_error,
    output reg  signed [XW-1:0]     x_centered
);

    reg signed [PW:0] centered_temp;
    reg signed [XW-1:0] centered_ext;

    always @* begin
        range_error = raw_range_error;

        if (candidate_base > half_range)
            centered_temp = $signed({1'b0, candidate_base}) - $signed({1'b0, M_base});
        else
            centered_temp = $signed({1'b0, candidate_base});

        centered_ext = {{(XW-(PW+1)){centered_temp[PW]}}, centered_temp};
        x_centered = centered_ext;
    end

endmodule

`timescale 1ns/1ps
module final_alu_subset_rom(
    input  wire [3:0] subset_id,
    output reg  [2:0] idx0,
    output reg  [2:0] idx1,
    output reg  [2:0] idx2,
    output reg  [2:0] idx3,
    output reg  [5:0] subset_mask
);
    always @* begin
        case (subset_id)
            4'd0:  begin idx0=3'd0; idx1=3'd1; idx2=3'd2; idx3=3'd3; end
            4'd1:  begin idx0=3'd0; idx1=3'd1; idx2=3'd2; idx3=3'd4; end
            4'd2:  begin idx0=3'd0; idx1=3'd1; idx2=3'd2; idx3=3'd5; end
            4'd3:  begin idx0=3'd0; idx1=3'd1; idx2=3'd3; idx3=3'd4; end
            4'd4:  begin idx0=3'd0; idx1=3'd1; idx2=3'd3; idx3=3'd5; end
            4'd5:  begin idx0=3'd0; idx1=3'd1; idx2=3'd4; idx3=3'd5; end
            4'd6:  begin idx0=3'd0; idx1=3'd2; idx2=3'd3; idx3=3'd4; end
            4'd7:  begin idx0=3'd0; idx1=3'd2; idx2=3'd3; idx3=3'd5; end
            4'd8:  begin idx0=3'd0; idx1=3'd2; idx2=3'd4; idx3=3'd5; end
            4'd9:  begin idx0=3'd0; idx1=3'd3; idx2=3'd4; idx3=3'd5; end
            4'd10: begin idx0=3'd1; idx1=3'd2; idx2=3'd3; idx3=3'd4; end
            4'd11: begin idx0=3'd1; idx1=3'd2; idx2=3'd3; idx3=3'd5; end
            4'd12: begin idx0=3'd1; idx1=3'd2; idx2=3'd4; idx3=3'd5; end
            4'd13: begin idx0=3'd1; idx1=3'd3; idx2=3'd4; idx3=3'd5; end
            4'd14: begin idx0=3'd2; idx1=3'd3; idx2=3'd4; idx3=3'd5; end
            default: begin idx0=3'd0; idx1=3'd1; idx2=3'd2; idx3=3'd3; end
        endcase
        subset_mask = (6'b1 << idx0) | (6'b1 << idx1) | (6'b1 << idx2) | (6'b1 << idx3);
    end
endmodule

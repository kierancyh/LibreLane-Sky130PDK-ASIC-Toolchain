`timescale 1ns/1ps
module final_alu_cu (
    input  wire clk,
    input  wire rst_n,

    input  wire Start,
    output reg  Done,
    output wire [3:0] CU_state_dbg,

    input  wire Encode_Done,
    input  wire ALU_Done,
    input  wire Recon_Done,
    input  wire Correct_Done,

    output reg  Load_IN,
    output reg  Encode_EN,
    output reg  ALU_EN,
    output reg  Recon_Start,
    output reg  Correct_Start,
    output reg  Out_EN
);

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_LOAD       = 4'd1,
        S_ENCODE     = 4'd2,
        S_ALU        = 4'd3,
        S_RECON_PRE  = 4'd4,
        S_CORRECT    = 4'd5,
        S_RECON_POST = 4'd6,
        S_OUT        = 4'd7,
        S_DONE       = 4'd8;

    reg [3:0] state, next_state;

    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @* begin
        next_state = state;

        case (state)
            S_IDLE:       if (Start)        next_state = S_LOAD;
            S_LOAD:                         next_state = S_ENCODE;
            S_ENCODE:     if (Encode_Done)  next_state = S_ALU;
            S_ALU:        if (ALU_Done)     next_state = S_RECON_PRE;
            S_RECON_PRE:  if (Recon_Done)   next_state = S_CORRECT;
            S_CORRECT:    if (Correct_Done) next_state = S_RECON_POST;
            S_RECON_POST: if (Recon_Done)   next_state = S_OUT;
            S_OUT:                          next_state = S_DONE;
            S_DONE:       if (!Start)       next_state = S_IDLE;
            default:                        next_state = S_IDLE;
        endcase
    end

    always @* begin
        Load_IN       = 1'b0;
        Encode_EN     = 1'b0;
        ALU_EN        = 1'b0;
        Recon_Start   = 1'b0;
        Correct_Start = 1'b0;
        Out_EN        = 1'b0;
        Done          = 1'b0;

        case (state)
            S_LOAD:       Load_IN       = 1'b1;
            S_ENCODE:     Encode_EN     = 1'b1;
            S_ALU:        ALU_EN        = 1'b1;
            S_RECON_PRE,
            S_RECON_POST: Recon_Start   = 1'b1;
            S_CORRECT:    Correct_Start = 1'b1;
            S_OUT:        Out_EN        = 1'b1;
            S_DONE:       Done          = 1'b1;
        endcase
    end

    assign CU_state_dbg = state;

endmodule

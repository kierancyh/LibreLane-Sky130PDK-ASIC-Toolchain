`timescale 1ns/1ps
module final_alu_cfg_regs #(
    parameter integer WM = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 cfg_we,
    input  wire [3:0]           cfg_addr,
    input  wire [31:0]          cfg_wdata,
    input  wire                 allow_write,
    input  wire                 clear_loaded,

    output reg  [WM-1:0]        m0_reg,
    output reg  [WM-1:0]        m1_reg,
    output reg  [WM-1:0]        m2_reg,
    output reg  [WM-1:0]        m3_reg,
    output reg  [WM-1:0]        m4_reg,
    output reg  [WM-1:0]        m5_reg,
    output reg                  detect_en_reg,
    output reg                  correct_en_reg,
    output reg                  cfg_lock_reg,
    output reg                  cfg_loaded_reg
);

    always @(posedge clk) begin
        if (!rst_n) begin
            m0_reg         <= {WM{1'b0}};
            m1_reg         <= {WM{1'b0}};
            m2_reg         <= {WM{1'b0}};
            m3_reg         <= {WM{1'b0}};
            m4_reg         <= {WM{1'b0}};
            m5_reg         <= {WM{1'b0}};
            detect_en_reg  <= 1'b1;
            correct_en_reg <= 1'b1;
            cfg_lock_reg   <= 1'b0;
            cfg_loaded_reg <= 1'b0;
        end else begin
            if (clear_loaded) begin
                cfg_loaded_reg <= 1'b0;
            end
            if (cfg_we && allow_write) begin
                case (cfg_addr)
                    4'h0: begin
                        detect_en_reg  <= cfg_wdata[0];
                        correct_en_reg <= cfg_wdata[1] & cfg_wdata[0];
                        cfg_lock_reg   <= cfg_wdata[2];
                        cfg_loaded_reg <= 1'b1;
                    end
                    4'h1: begin m0_reg <= cfg_wdata[WM-1:0]; cfg_loaded_reg <= 1'b1; end
                    4'h2: begin m1_reg <= cfg_wdata[WM-1:0]; cfg_loaded_reg <= 1'b1; end
                    4'h3: begin m2_reg <= cfg_wdata[WM-1:0]; cfg_loaded_reg <= 1'b1; end
                    4'h4: begin m3_reg <= cfg_wdata[WM-1:0]; cfg_loaded_reg <= 1'b1; end
                    4'h5: begin m4_reg <= cfg_wdata[WM-1:0]; cfg_loaded_reg <= 1'b1; end
                    4'h6: begin m5_reg <= cfg_wdata[WM-1:0]; cfg_loaded_reg <= 1'b1; end
                    default: begin end
                endcase
            end
        end
    end

endmodule

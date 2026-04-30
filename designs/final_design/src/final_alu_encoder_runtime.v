`timescale 1ns/1ps

// Sequential runtime encoder.
// This replaces the previous task/function based modulo reduction, which
// synthesized into a very large combinational subtract/mux network.
//
// Operation:
//   - one encoder instance is already shared by the top for A then B
//   - this module reduces one input bit per clock, one lane at a time
//   - latency is higher, but area is much smaller and Yosys-friendly
module final_alu_encoder_runtime #(
    parameter integer WM = 5,
    parameter integer XW = 24
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire signed [XW-1:0] x_in,
    input  wire [WM-1:0]        m0,
    input  wire [WM-1:0]        m1,
    input  wire [WM-1:0]        m2,
    input  wire [WM-1:0]        m3,
    input  wire [WM-1:0]        m4,
    input  wire [WM-1:0]        m5,
    output reg                  done,
    output reg  [6*WM-1:0]      res_flat
);

    // Manual one-hot FSM. This prevents start/state from becoming one
    // high-load mux-select net for the encoder work-register bank.
    localparam [5:0]
        ST_IDLE   = 6'b000001,
        ST_INIT0  = 6'b000010,
        ST_INIT1  = 6'b000100,
        ST_INIT2  = 6'b001000,
        ST_BITS   = 6'b010000,
        ST_STORE  = 6'b100000;

    (* keep = "true" *) reg [5:0]      state;
    reg [2:0]      lane_idx;
    reg [5:0]      bit_count;      // XW is 24 in this project envelope
    reg [XW-1:0]   mag_reg;
    reg [XW-1:0]   shift_reg;
    reg            neg_reg;
    reg [WM-1:0]   modulus_reg;
    reg [WM:0]     rem_reg;
    reg [WM:0]     rem_shift;
    reg [WM:0]     rem_next;
    reg [WM-1:0]   residue_next;

    wire [XW-1:0] abs_x_wire;
    assign abs_x_wire = x_in[XW-1] ? (~x_in + {{(XW-1){1'b0}}, 1'b1}) : x_in;

    always @* begin
        rem_shift = {rem_reg[WM-1:0], shift_reg[XW-1]};
        if (modulus_reg <= {{(WM-1){1'b0}}, 1'b1}) begin
            rem_next = {(WM+1){1'b0}};
        end else if (rem_shift >= {1'b0, modulus_reg}) begin
            rem_next = rem_shift - {1'b0, modulus_reg};
        end else begin
            rem_next = rem_shift;
        end

        if (modulus_reg <= {{(WM-1){1'b0}}, 1'b1}) begin
            residue_next = {WM{1'b0}};
        end else if (neg_reg && (rem_reg[WM-1:0] != {WM{1'b0}})) begin
            residue_next = modulus_reg - rem_reg[WM-1:0];
        end else begin
            residue_next = rem_reg[WM-1:0];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            lane_idx  <= 3'd0;
            bit_count <= 6'd0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state <= ST_INIT0;
                    end
                end

                /*
                 * Physical-signoff patch:
                 * V10 still had one encoder-start decode feeding the 24-bit
                 * mag/shift load muxes.  Stagger the capture so start only
                 * changes the state flop, and each init state drives a smaller
                 * local bank of registers.
                 */
                ST_INIT0: begin
                    lane_idx    <= 3'd0;
                    bit_count   <= XW[5:0];
                    neg_reg     <= x_in[XW-1];
                    modulus_reg <= m0;
                    rem_reg     <= {(WM+1){1'b0}};
                    state       <= ST_INIT1;
                end

                ST_INIT1: begin
                    mag_reg[11:0]   <= abs_x_wire[11:0];
                    shift_reg[11:0] <= abs_x_wire[11:0];
                    state           <= ST_INIT2;
                end

                ST_INIT2: begin
                    mag_reg[XW-1:12]   <= abs_x_wire[XW-1:12];
                    shift_reg[XW-1:12] <= abs_x_wire[XW-1:12];
                    state              <= ST_BITS;
                end

                ST_BITS: begin
                    if (bit_count != 6'd0) begin
                        rem_reg   <= rem_next;
                        shift_reg <= {shift_reg[XW-2:0], 1'b0};
                        bit_count <= bit_count - 6'd1;
                    end else begin
                        state <= ST_STORE;
                    end
                end

                ST_STORE: begin
                    case (lane_idx)
                        3'd0: res_flat[(0*WM)+:WM] <= residue_next;
                        3'd1: res_flat[(1*WM)+:WM] <= residue_next;
                        3'd2: res_flat[(2*WM)+:WM] <= residue_next;
                        3'd3: res_flat[(3*WM)+:WM] <= residue_next;
                        3'd4: res_flat[(4*WM)+:WM] <= residue_next;
                        3'd5: res_flat[(5*WM)+:WM] <= residue_next;
                        default: begin end
                    endcase

                    if (lane_idx == 3'd5) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        lane_idx  <= lane_idx + 3'd1;
                        bit_count <= XW[5:0];
                        shift_reg <= mag_reg;
                        rem_reg   <= {(WM+1){1'b0}};
                        case (lane_idx + 3'd1)
                            3'd1: modulus_reg <= m1;
                            3'd2: modulus_reg <= m2;
                            3'd3: modulus_reg <= m3;
                            3'd4: modulus_reg <= m4;
                            3'd5: modulus_reg <= m5;
                            default: modulus_reg <= {WM{1'b0}};
                        endcase
                        state <= ST_BITS;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

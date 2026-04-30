`timescale 1ns/1ps
// V20 source marker: config checker has no wide enabled M_base commit mux.
module final_alu_cfg_checker #(
    parameter integer WM = 5,
    parameter integer XW = 24,
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
    output reg                  done,
    output reg                  cfg_ok,
    output reg  [3:0]           cfg_error_code,
    output reg  [PW-1:0]        M_base,
    output reg  [PW-1:0]        half_range
);

    // V17 physical-signoff patch:
    // Use an explicit one-hot state register for the config checker.
    localparam [12:0]
        ST_IDLE         = 13'b0000000000001,
        ST_BASIC        = 13'b0000000000010,
        ST_DISTINCT     = 13'b0000000000100,
        ST_GCD_INIT     = 13'b0000000001000,
        ST_GCD_STEP     = 13'b0000000010000,
        ST_BASE_INIT    = 13'b0000000100000,
        ST_BASE_MUL     = 13'b0000001000000,
        ST_BASE_CHECK   = 13'b0000010000000,
        ST_SUBSET_INIT  = 13'b0000100000000,
        ST_SUBSET_MUL   = 13'b0001000000000,
        ST_SUBSET_CHECK = 13'b0010000000000,
        ST_DONE         = 13'b0100000000000,
        ST_ERROR        = 13'b1000000000000;

    // With WM=5, the largest legal 4-lane product is 31^4 = 923521,
    // so the internal product/candidate width can be reduced to PW=20.
    // The previous RANGE_LIMIT compare was redundant for the current
    // WM=5/PW=20 envelope: 31^4 = 923521 fits in 20 bits.  Removing that
    // impossible compare avoids a high-load comparator cone in signoff.

    (* keep = "true" *) reg [12:0] state;

    /*
     * V20 physical-signoff cleanup:
     * The V19 post-PnR report showed the worst slew/cap net was the
     * checker M_base commit select feeding all 20 output bits.  M_base is
     * purely the product of the four base moduli, and WM=5 guarantees
     * the product fits in PW=20.  Keep M_base/half_range in a tiny
     * always-updated register bank instead of an enabled commit mux.
     */
    wire [(2*WM)-1:0] base_m01_wire;
    wire [(2*WM)-1:0] base_m23_wire;
    wire [(4*WM)-1:0] base_product_small_wire;
    wire [PW-1:0]     base_product_wire;

    assign base_m01_wire = m0 * m1;
    assign base_m23_wire = m2 * m3;
    assign base_product_small_wire = base_m01_wire * base_m23_wire;
    assign base_product_wire = base_product_small_wire[PW-1:0];

    reg [WM-1:0] lm0, lm1, lm2, lm3, lm4, lm5;
    reg [2:0]    mod_idx;
    reg [2:0]    pair_i, pair_j;
    reg [WM-1:0] gcd_a, gcd_b;
    reg [2:0]    si, sj, sk, sl;
    reg [1:0]    mul_stage;
    reg [PW-1:0] subset_acc;

    reg [WM-1:0] mod_sel;
    reg [WM-1:0] pair_mod_i;
    reg [WM-1:0] pair_mod_j;

    always @* begin
        case (mod_idx)
            3'd0: mod_sel = lm0;
            3'd1: mod_sel = lm1;
            3'd2: mod_sel = lm2;
            3'd3: mod_sel = lm3;
            3'd4: mod_sel = lm4;
            3'd5: mod_sel = lm5;
            default: mod_sel = {WM{1'b0}};
        endcase
    end

    always @* begin
        case (pair_i)
            3'd0: pair_mod_i = lm0;
            3'd1: pair_mod_i = lm1;
            3'd2: pair_mod_i = lm2;
            3'd3: pair_mod_i = lm3;
            3'd4: pair_mod_i = lm4;
            3'd5: pair_mod_i = lm5;
            default: pair_mod_i = {WM{1'b0}};
        endcase
    end

    always @* begin
        case (pair_j)
            3'd0: pair_mod_j = lm0;
            3'd1: pair_mod_j = lm1;
            3'd2: pair_mod_j = lm2;
            3'd3: pair_mod_j = lm3;
            3'd4: pair_mod_j = lm4;
            3'd5: pair_mod_j = lm5;
            default: pair_mod_j = {WM{1'b0}};
        endcase
    end


    always @(posedge clk) begin
        M_base     <= base_product_wire;
        half_range <= (base_product_wire >> 1);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            done           <= 1'b0;
            cfg_ok         <= 1'b0;
            cfg_error_code <= 4'd0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        lm0            <= m0;
                        lm1            <= m1;
                        lm2            <= m2;
                        lm3            <= m3;
                        lm4            <= m4;
                        lm5            <= m5;
                        cfg_ok         <= 1'b0;
                        cfg_error_code <= 4'd0;
                        mod_idx        <= 3'd0;
                        pair_i         <= 3'd0;
                        pair_j         <= 3'd1;
                        gcd_a          <= {WM{1'b0}};
                        gcd_b          <= {WM{1'b0}};
                        si             <= 3'd0;
                        sj             <= 3'd1;
                        sk             <= 3'd2;
                        sl             <= 3'd3;
                        mul_stage      <= 2'd0;
                        subset_acc     <= {PW{1'b0}};
                        state          <= ST_BASIC;
                    end
                end

                ST_BASIC: begin
                    if (mod_sel <= {{(WM-1){1'b0}}, 1'b1}) begin
                        cfg_error_code <= 4'd1;
                        state          <= ST_ERROR;
                    end else if (mod_idx == 3'd5) begin
                        pair_i <= 3'd0;
                        pair_j <= 3'd1;
                        state  <= ST_DISTINCT;
                    end else begin
                        mod_idx <= mod_idx + 3'd1;
                    end
                end

                ST_DISTINCT: begin
                    if (pair_mod_i == pair_mod_j) begin
                        cfg_error_code <= 4'd2;
                        state          <= ST_ERROR;
                    end else begin
                        state <= ST_GCD_INIT;
                    end
                end

                ST_GCD_INIT: begin
                    gcd_a <= pair_mod_i;
                    gcd_b <= pair_mod_j;
                    state <= ST_GCD_STEP;
                end

                ST_GCD_STEP: begin
                    if (gcd_b != {WM{1'b0}}) begin
                        gcd_a <= gcd_b;
                        gcd_b <= gcd_a % gcd_b;
                    end else if (gcd_a != {{(WM-1){1'b0}}, 1'b1}) begin
                        cfg_error_code <= 4'd3;
                        state          <= ST_ERROR;
                    end else if (pair_i == 3'd4 && pair_j == 3'd5) begin
                        // All legal 5-bit base products fit in PW=20, so once
                        // every pair has passed the GCD test the configuration
                        // is accepted.  M_base/half_range are updated by the
                        // small always-on register bank below.
                        state     <= ST_DONE;
                    end else begin
                        if (pair_j == 3'd5) begin
                            pair_i <= pair_i + 3'd1;
                            pair_j <= pair_i + 3'd2;
                        end else begin
                            pair_j <= pair_j + 3'd1;
                        end
                        state <= ST_DISTINCT;
                    end
                end

                ST_SUBSET_MUL: begin
                    // Legacy state retained for encoding compatibility only.
                    state <= ST_DONE;
                end

                ST_SUBSET_CHECK: begin
                    // Legacy state retained for encoding compatibility only.
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    cfg_ok         <= 1'b1;
                    cfg_error_code <= 4'd0;
                    done           <= 1'b1;
                    state          <= ST_IDLE;
                end

                ST_ERROR: begin
                    cfg_ok <= 1'b0;
                    done   <= 1'b1;
                    state  <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

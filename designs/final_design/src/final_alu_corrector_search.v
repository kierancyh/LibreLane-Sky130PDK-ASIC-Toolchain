`timescale 1ns/1ps
// V18 source marker: module renamed to prevent stale corrector source from silently compiling.
// V50A source marker: corrector has registered final-output boundary.
// V52H source marker: corrector exits on first valid single-lane candidate to remove corr_candidate hold fanout.
// V18 source marker: corrector has no wide input-capture register bank.
module final_alu_corrector_search_v18 #(
    parameter integer WM = 5,
    parameter integer PW = 20
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire                 enable_detection,
    input  wire                 enable_correction,
    input  wire [6*WM-1:0]      z_res_flat,
    input  wire [PW-1:0]        M_base,
    input  wire [14:0]          usable_subset_bitmap,
    input  wire [WM-1:0]        m0,
    input  wire [WM-1:0]        m1,
    input  wire [WM-1:0]        m2,
    input  wire [WM-1:0]        m3,
    input  wire [WM-1:0]        m4,
    input  wire [WM-1:0]        m5,
    output reg                  done,
    output reg                  residue_error,
    output reg                  corrected_success,
    output reg                  uncorrectable,
    output reg  [5:0]           corrected_lane_mask,
    output reg  [5:0]           mismatch_mask_out,
    output reg  [2:0]           mismatch_count_out,
    output reg  [PW-1:0]        corrected_candidate_base
);

    /*
     * V15 physical-signoff patch:
     *   - Keep the one-hot sequential candidate scan.
     *   - Remove the large corrector input-capture bank from V14.
     *
     * The top-level wrapper locks configuration writes while Busy is high, so
     * M_base, m0..m5, enable_detection/enable_correction, and z_res_flat are
     * stable for the whole correction operation.  Therefore the corrector uses
     * those stable inputs directly instead of copying them into a wide local
     * input-register bank.
     *
     * Removing that capture bank directly attacks the old wide input-capture
     * mux-select slew cluster.  The datapath also advances its residue counters without
     * using last_candidate as the hold/update select, which attacks the V14
     * _01641_ comparator fanout cluster.
     */
    localparam [7:0] ST_IDLE      = 8'b00000001;
    localparam [7:0] ST_INIT_CTRL = 8'b00000010;
    localparam [7:0] ST_INIT_L01  = 8'b00000100;
    localparam [7:0] ST_INIT_L23  = 8'b00001000;
    localparam [7:0] ST_INIT_L45  = 8'b00010000;
    localparam [7:0] ST_SCAN      = 8'b00100000;
    localparam [7:0] ST_FINALIZE  = 8'b01000000;
    localparam [7:0] ST_DONE      = 8'b10000000;

    wire [WM-1:0] z0 = z_res_flat[(0*WM)+:WM];
    wire [WM-1:0] z1 = z_res_flat[(1*WM)+:WM];
    wire [WM-1:0] z2 = z_res_flat[(2*WM)+:WM];
    wire [WM-1:0] z3 = z_res_flat[(3*WM)+:WM];
    wire [WM-1:0] z4 = z_res_flat[(4*WM)+:WM];
    wire [WM-1:0] z5 = z_res_flat[(5*WM)+:WM];

    (* keep = "true" *) reg [7:0] state;
    reg [PW-1:0] cand;

    reg [WM-1:0] p0;
    reg [WM-1:0] p1;
    reg [WM-1:0] p2;
    reg [WM-1:0] p3;
    reg [WM-1:0] p4;
    reg [WM-1:0] p5;

    (* keep = "true", dont_touch = "true" *) reg half_hit0_q;
    (* keep = "true", dont_touch = "true" *) reg half_hit1_q;
    (* keep = "true", dont_touch = "true" *) reg half_hit2_q;
    (* keep = "true", dont_touch = "true" *) reg half_hit3_q;
    (* keep = "true", dont_touch = "true" *) reg half_hit4_q;
    (* keep = "true", dont_touch = "true" *) reg half_hit5_q;

    reg          base_found;
    reg [PW-1:0] base_candidate;
    reg [5:0]    base_mask;
    reg [2:0]    base_count;

    reg [5:0] cmp_mask;
    reg [2:0] cmp_count;

    reg          final_residue_error_q;
    reg          final_corrected_success_q;
    reg          final_uncorrectable_q;
    reg [5:0]    final_corrected_lane_mask_q;
    reg [5:0]    final_mismatch_mask_q;
    reg [2:0]    final_mismatch_count_q;
    reg [PW-1:0] final_corrected_candidate_base_q;


    wire [PW-1:0] zero_pw = {PW{1'b0}};
    wire [PW-1:0] one_pw  = {{(PW-1){1'b0}}, 1'b1};
    wire [PW-1:0] cand_plus_one = cand + one_pw;
    wire [PW-1:0] half_base_wire = (M_base >> 1);
    wire          last_candidate = (cand_plus_one >= M_base);
    wire          next_half_hit  = (cand_plus_one == half_base_wire);

    wire          base_match = (p0 == z0) && (p1 == z1) && (p2 == z2) && (p3 == z3);
    wire          corr_this = enable_correction && (cmp_count == 3'd1);
    wire          base_found_final = base_found || base_match;
    wire [PW-1:0] base_candidate_final = base_found ? base_candidate : cand;
    wire [5:0]    base_mask_final = base_found ? base_mask : cmp_mask;
    wire [2:0]    base_count_final = base_found ? base_count : cmp_count;

    // Retained for wrapper compatibility.  The current scan engine does not
    // need the precomputed subset bitmap.
    wire unused_subset_bitmap = |usable_subset_bitmap;

    always @(*) begin
        cmp_mask  = 6'd0;
        cmp_count = 3'd0;

        if (p0 != z0) begin cmp_mask[0] = 1'b1; cmp_count = cmp_count + 3'd1; end
        if (p1 != z1) begin cmp_mask[1] = 1'b1; cmp_count = cmp_count + 3'd1; end
        if (p2 != z2) begin cmp_mask[2] = 1'b1; cmp_count = cmp_count + 3'd1; end
        if (p3 != z3) begin cmp_mask[3] = 1'b1; cmp_count = cmp_count + 3'd1; end
        if (p4 != z4) begin cmp_mask[4] = 1'b1; cmp_count = cmp_count + 3'd1; end
        if (p5 != z5) begin cmp_mask[5] = 1'b1; cmp_count = cmp_count + 3'd1; end
    end

    /* Reset-minimal control block.  Only state/done reset. */
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state <= ST_INIT_CTRL;
                    end
                end

                ST_INIT_CTRL: begin
                    if (M_base == zero_pw)
                        state <= ST_FINALIZE;
                    else
                        state <= ST_INIT_L01;
                end

                ST_INIT_L01: begin
                    state <= ST_INIT_L23;
                end

                ST_INIT_L23: begin
                    state <= ST_INIT_L45;
                end

                ST_INIT_L45: begin
                    state <= ST_SCAN;
                end

                ST_SCAN: begin
                    if (!enable_detection) begin
                        state <= ST_FINALIZE;
                    end else if (cmp_count == 3'd0) begin
                        state <= ST_FINALIZE;
                    end else if (corr_this) begin
                        state <= ST_FINALIZE;
                    end else if (last_candidate) begin
                        state <= ST_FINALIZE;
                    end
                end

                ST_FINALIZE: begin
                    state <= ST_DONE;
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    /* Datapath/status block: deliberately no reset gating. */
    always @(posedge clk) begin
        case (state)
            ST_INIT_CTRL: begin
                cand <= zero_pw;

                base_found     <= 1'b0;
                base_candidate <= zero_pw;
                base_mask      <= 6'd0;
                base_count     <= 3'd0;

                final_residue_error_q            <= 1'b0;
                final_corrected_success_q        <= 1'b0;
                final_uncorrectable_q            <= 1'b0;
                final_corrected_lane_mask_q      <= 6'd0;
                final_mismatch_mask_q            <= 6'd0;
                final_mismatch_count_q           <= 3'd0;
                final_corrected_candidate_base_q <= zero_pw;

                if (M_base == zero_pw) begin
                    final_residue_error_q            <= 1'b1;
                    final_corrected_success_q        <= 1'b0;
                    final_uncorrectable_q            <= 1'b1;
                    final_corrected_lane_mask_q      <= 6'd0;
                    final_mismatch_mask_q            <= 6'd0;
                    final_mismatch_count_q           <= 3'd0;
                    final_corrected_candidate_base_q <= zero_pw;
                end
            end

            ST_INIT_L01: begin
                p0 <= {WM{1'b0}};
                p1 <= {WM{1'b0}};
                half_hit0_q <= (zero_pw == half_base_wire);
                half_hit1_q <= (zero_pw == half_base_wire);
            end

            ST_INIT_L23: begin
                p2 <= {WM{1'b0}};
                p3 <= {WM{1'b0}};
                half_hit2_q <= (zero_pw == half_base_wire);
                half_hit3_q <= (zero_pw == half_base_wire);
            end

            ST_INIT_L45: begin
                p4 <= {WM{1'b0}};
                p5 <= {WM{1'b0}};
                half_hit4_q <= (zero_pw == half_base_wire);
                half_hit5_q <= (zero_pw == half_base_wire);
            end

            ST_SCAN: begin
                if (!enable_detection) begin
                    final_residue_error_q            <= 1'b0;
                    final_corrected_success_q        <= 1'b0;
                    final_uncorrectable_q            <= 1'b0;
                    final_corrected_lane_mask_q      <= 6'd0;
                    final_mismatch_mask_q            <= 6'd0;
                    final_mismatch_count_q           <= 3'd0;
                    final_corrected_candidate_base_q <= cand;
                end else if (cmp_count == 3'd0) begin
                    // A clean all-lane match is unique enough to stop early.
                    final_residue_error_q            <= 1'b0;
                    final_corrected_success_q        <= 1'b0;
                    final_uncorrectable_q            <= 1'b0;
                    final_corrected_lane_mask_q      <= 6'd0;
                    final_mismatch_mask_q            <= 6'd0;
                    final_mismatch_count_q           <= 3'd0;
                    final_corrected_candidate_base_q <= cand;
                end else if (corr_this) begin
                    /*
                     * V52H: under the single-lane RRNS fault model, the first
                     * candidate with exactly one mismatching residue is the
                     * corrected scalar candidate.  Finalising here removes the
                     * old corr_candidate/corr_mask storage bank, whose shared
                     * hold/update control became the dominant V52G max-slew
                     * source after the top-level and range-guard cleanups.
                     */
                    final_residue_error_q            <= 1'b1;
                    final_corrected_success_q        <= 1'b1;
                    final_uncorrectable_q            <= 1'b0;
                    final_corrected_lane_mask_q      <= cmp_mask;
                    final_mismatch_mask_q            <= cmp_mask;
                    final_mismatch_count_q           <= 3'd1;
                    final_corrected_candidate_base_q <= cand;
                end else begin
                    if (!base_found && base_match) begin
                        base_found     <= 1'b1;
                        base_candidate <= cand;
                        base_mask      <= cmp_mask;
                        base_count     <= cmp_count;
                    end

                    if (last_candidate) begin
                        if (base_found_final) begin
                            final_residue_error_q            <= (base_count_final != 3'd0);
                            final_corrected_success_q        <= 1'b0;
                            final_uncorrectable_q            <= enable_correction && (base_count_final > 3'd1);
                            final_corrected_lane_mask_q      <= 6'd0;
                            final_mismatch_mask_q            <= base_mask_final;
                            final_mismatch_count_q           <= base_count_final;
                            final_corrected_candidate_base_q <= base_candidate_final;
                        end else begin
                            final_residue_error_q            <= 1'b1;
                            final_corrected_success_q        <= 1'b0;
                            final_uncorrectable_q            <= enable_correction;
                            final_corrected_lane_mask_q      <= 6'd0;
                            final_mismatch_mask_q            <= cmp_mask;
                            final_mismatch_count_q           <= cmp_count;
                            final_corrected_candidate_base_q <= cand;
                        end
                    end

                    /*
                     * Advance the residue scan every active scan cycle, even
                     * on the terminal candidate.  On the terminal cycle these
                     * next residue/candidate values are unused because the FSM moves to
                     * ST_DONE, but avoiding a last_candidate-controlled hold
                     * mux removes that comparator from the lane-update cones.
                     */
                    cand <= cand_plus_one;
                    half_hit0_q <= next_half_hit;
                    half_hit1_q <= next_half_hit;
                    half_hit2_q <= next_half_hit;
                    half_hit3_q <= next_half_hit;
                    half_hit4_q <= next_half_hit;
                    half_hit5_q <= next_half_hit;

                    if (half_hit0_q) begin
                        if ((m0 <= 1) || (p0 == {WM{1'b0}})) p0 <= {WM{1'b0}}; else p0 <= m0 - p0;
                    end else begin
                        if ((m0 <= 1) || ((p0 + {{(WM-1){1'b0}},1'b1}) >= m0)) p0 <= {WM{1'b0}}; else p0 <= p0 + {{(WM-1){1'b0}},1'b1};
                    end

                    if (half_hit1_q) begin
                        if ((m1 <= 1) || (p1 == {WM{1'b0}})) p1 <= {WM{1'b0}}; else p1 <= m1 - p1;
                    end else begin
                        if ((m1 <= 1) || ((p1 + {{(WM-1){1'b0}},1'b1}) >= m1)) p1 <= {WM{1'b0}}; else p1 <= p1 + {{(WM-1){1'b0}},1'b1};
                    end

                    if (half_hit2_q) begin
                        if ((m2 <= 1) || (p2 == {WM{1'b0}})) p2 <= {WM{1'b0}}; else p2 <= m2 - p2;
                    end else begin
                        if ((m2 <= 1) || ((p2 + {{(WM-1){1'b0}},1'b1}) >= m2)) p2 <= {WM{1'b0}}; else p2 <= p2 + {{(WM-1){1'b0}},1'b1};
                    end

                    if (half_hit3_q) begin
                        if ((m3 <= 1) || (p3 == {WM{1'b0}})) p3 <= {WM{1'b0}}; else p3 <= m3 - p3;
                    end else begin
                        if ((m3 <= 1) || ((p3 + {{(WM-1){1'b0}},1'b1}) >= m3)) p3 <= {WM{1'b0}}; else p3 <= p3 + {{(WM-1){1'b0}},1'b1};
                    end

                    if (half_hit4_q) begin
                        if ((m4 <= 1) || (p4 == {WM{1'b0}})) p4 <= {WM{1'b0}}; else p4 <= m4 - p4;
                    end else begin
                        if ((m4 <= 1) || ((p4 + {{(WM-1){1'b0}},1'b1}) >= m4)) p4 <= {WM{1'b0}}; else p4 <= p4 + {{(WM-1){1'b0}},1'b1};
                    end

                    if (half_hit5_q) begin
                        if ((m5 <= 1) || (p5 == {WM{1'b0}})) p5 <= {WM{1'b0}}; else p5 <= m5 - p5;
                    end else begin
                        if ((m5 <= 1) || ((p5 + {{(WM-1){1'b0}},1'b1}) >= m5)) p5 <= {WM{1'b0}}; else p5 <= p5 + {{(WM-1){1'b0}},1'b1};
                    end
                end
            end

            ST_FINALIZE: begin
                residue_error            <= final_residue_error_q;
                corrected_success        <= final_corrected_success_q;
                uncorrectable            <= final_uncorrectable_q;
                corrected_lane_mask      <= final_corrected_lane_mask_q;
                mismatch_mask_out        <= final_mismatch_mask_q;
                mismatch_count_out       <= final_mismatch_count_q;
                corrected_candidate_base <= final_corrected_candidate_base_q;
            end

            default: begin
            end
        endcase
    end

endmodule

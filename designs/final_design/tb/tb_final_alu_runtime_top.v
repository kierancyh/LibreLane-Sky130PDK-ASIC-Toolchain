`timescale 1ns/1ps

module tb_final_alu_runtime_top;

    reg clk;
    reg rst_n;

    reg         cfg_we;
    reg         cfg_re;
    reg  [3:0]  cfg_addr;
    reg  [31:0] cfg_wdata;
    reg         cfg_apply;
    wire [31:0] cfg_rdata;

    reg         Load_IN;
    reg  [1:0]  Op_Sel;
    reg  signed [23:0] A_in;
    reg  signed [23:0] B_in;

    wire signed [23:0] X_out;
    wire Done;
    wire Busy;
    wire Config_Valid;
    wire Config_Busy;
    wire Config_Error;
    wire [3:0] Config_Error_Code;
    wire Error_Detected;
    wire Corrected;
    wire Valid;
    wire Uncorrectable;

    integer op_cycle_count;
    integer op_start_time;
    integer op_end_time;
    reg [5:0] forced_lane_value;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    final_alu_runtime_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_we(cfg_we),
        .cfg_re(cfg_re),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_apply(cfg_apply),
        .cfg_rdata(cfg_rdata),
        .Load_IN(Load_IN),
        .Op_Sel(Op_Sel),
        .A_in(A_in),
        .B_in(B_in),
        .X_out(X_out),
        .Done(Done),
        .Busy(Busy),
        .Config_Valid(Config_Valid),
        .Config_Busy(Config_Busy),
        .Config_Error(Config_Error),
        .Config_Error_Code(Config_Error_Code),
        .Error_Detected(Error_Detected),
        .Corrected(Corrected),
        .Valid(Valid),
        .Uncorrectable(Uncorrectable)
    );

    initial begin
        $dumpfile("final_alu_runtime_rtl.vcd");
        $dumpvars(0, tb_final_alu_runtime_top);
    end

    task cfg_write_word;
        input [3:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            cfg_we    <= 1'b1;
            cfg_addr  <= addr;
            cfg_wdata <= data;
            @(posedge clk);
            cfg_we    <= 1'b0;
            cfg_addr  <= 4'd0;
            cfg_wdata <= 32'd0;
        end
    endtask

    task cfg_apply_pulse;
        begin
            @(posedge clk);
            cfg_apply <= 1'b1;
            @(posedge clk);
            cfg_apply <= 1'b0;
        end
    endtask

    task wait_cfg_ready;
        integer timeout;
        begin
            timeout = 0;
            // Wait for the current config transaction to fully settle.
            // This avoids returning early on stale Config_Valid during reconfiguration.
            while (((!Config_Valid && !Config_Error) || Config_Busy) && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 2000) begin
                $display("[FAIL] configuration timeout");
                $fatal(1);
            end
        end
    endtask

    task program_config;
        input integer detect_en;
        input integer corr_en;
        input integer m0;
        input integer m1;
        input integer m2;
        input integer m3;
        input integer m4;
        input integer m5;
        begin
            $display("CONFIG APPLY  detect=%0d  corr=%0d  moduli={%0d,%0d,%0d,%0d,%0d,%0d}",
                     detect_en, corr_en, m0, m1, m2, m3, m4, m5);
            cfg_write_word(4'h0, {29'd0, 1'b0, corr_en[0], detect_en[0]});
            cfg_write_word(4'h1, m0);
            cfg_write_word(4'h2, m1);
            cfg_write_word(4'h3, m2);
            cfg_write_word(4'h4, m3);
            cfg_write_word(4'h5, m4);
            cfg_write_word(4'h6, m5);
            cfg_apply_pulse();
            @(posedge clk);
            wait_cfg_ready();
            if (!Config_Valid) begin
                $display("[FAIL] config invalid, code=%0d", Config_Error_Code);
                $fatal(1);
            end
            $display("CONFIG READY  M_base=%0d  half_range=%0d", dut.M_base_reg, dut.half_range_reg);
            $display("");
        end
    endtask

    task start_operation;
        input integer a_val;
        input integer b_val;
        input [1:0] op;
        begin
            op_cycle_count = 0;
            op_start_time  = $time;
            $display("TEST START    op=%0s  A=%0d  B=%0d  cfg={%0d,%0d,%0d,%0d,%0d,%0d}",
                     (op == 2'b00) ? "ADD" :
                     (op == 2'b01) ? "SUB" :
                     (op == 2'b10) ? "MUL" : "UNK",
                     a_val, b_val,
                     dut.m0_cfg, dut.m1_cfg, dut.m2_cfg, dut.m3_cfg, dut.m4_cfg, dut.m5_cfg);
            @(posedge clk);
            A_in    <= a_val;
            B_in    <= b_val;
            Op_Sel  <= op;
            Load_IN <= 1'b1;
            @(posedge clk);
            Load_IN <= 1'b0;
        end
    endtask

    task wait_done_pulse;
        integer timeout;
        begin
            timeout = 0;
            while (!Done && timeout < 20000) begin
                @(posedge clk);
                timeout = timeout + 1;
                op_cycle_count = op_cycle_count + 1;
            end
            if (timeout >= 20000) begin
                $display("[FAIL] operation timeout");
                $fatal(1);
            end
            op_end_time = $time;
        end
    endtask

    task inject_fault_before_corrector;
        input integer lane;
        begin
            // Wait until the final lane result has been produced, but before correction starts.
            while (!(dut.op_state_dbg == 4'd4 && dut.lane_idx == 3'd5 && dut.slice_done))
                @(posedge clk);
            #1;
            case (lane)
                0: begin
                    forced_lane_value = (dut.z0_reg == 0) ? 6'd1 : 6'd0;
                    dut.z0_reg = forced_lane_value;
                end
                1: begin
                    forced_lane_value = (dut.z1_reg == 0) ? 6'd1 : 6'd0;
                    dut.z1_reg = forced_lane_value;
                end
                2: begin
                    forced_lane_value = (dut.z2_reg == 0) ? 6'd1 : 6'd0;
                    dut.z2_reg = forced_lane_value;
                end
                3: begin
                    forced_lane_value = (dut.z3_reg == 0) ? 6'd1 : 6'd0;
                    dut.z3_reg = forced_lane_value;
                end
                4: begin
                    forced_lane_value = dut.z4_reg + 6'd1;
                    dut.z4_reg = forced_lane_value;
                end
                5: begin
                    forced_lane_value = dut.z5_reg + 6'd1;
                    dut.z5_reg = forced_lane_value;
                end
                default: begin end
            endcase
        end
    endtask

    task release_faults;
        begin
            forced_lane_value = 6'd0;
        end
    endtask

    task check_result;
        input integer exp_x;
        input integer exp_err;
        input integer exp_corr;
        input integer exp_valid;
        input integer exp_uncorr;
        input [255:0] label;
        begin
            wait_done_pulse();
            #1;
            $display("RESULT %-28s | got: X=%0d err=%0d corr=%0d valid=%0d uncorr=%0d | exp: X=%0d err=%0d corr=%0d valid=%0d uncorr=%0d | cycles=%0d time=%0d ns",
                     label, $signed(X_out), Error_Detected, Corrected, Valid, Uncorrectable,
                     exp_x, exp_err, exp_corr, exp_valid, exp_uncorr,
                     op_cycle_count, (op_end_time - op_start_time));
            $display("DETAIL        lanes z={%0d,%0d,%0d,%0d,%0d,%0d}  mismatch_mask=%06b  mismatch_count=%0d  corrected_lane_mask=%06b  candidate_base=%0d  state=%0d",
                     dut.z0_reg, dut.z1_reg, dut.z2_reg, dut.z3_reg, dut.z4_reg, dut.z5_reg,
                     dut.corrector_mismatch_mask, dut.corrector_mismatch_count,
                     dut.corrector_lane_mask, dut.corrector_candidate_base,
                     dut.op_state_dbg);
            if ($signed(X_out) !== exp_x) begin
                $display("[FAIL] %0s: expected X=%0d got %0d", label, exp_x, $signed(X_out));
                $fatal(1);
            end
            if (Error_Detected !== exp_err[0]) begin
                $display("[FAIL] %0s: expected err=%0d got %0d", label, exp_err, Error_Detected);
                $fatal(1);
            end
            if (Corrected !== exp_corr[0]) begin
                $display("[FAIL] %0s: expected corr=%0d got %0d", label, exp_corr, Corrected);
                $fatal(1);
            end
            if (Valid !== exp_valid[0]) begin
                $display("[FAIL] %0s: expected valid=%0d got %0d", label, exp_valid, Valid);
                $fatal(1);
            end
            if (Uncorrectable !== exp_uncorr[0]) begin
                $display("[FAIL] %0s: expected uncorr=%0d got %0d", label, exp_uncorr, Uncorrectable);
                $fatal(1);
            end
            $display("[PASS] %0s", label);
            $display("");
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n     = 1'b0;
        cfg_we    = 1'b0;
        cfg_re    = 1'b0;
        cfg_addr  = 4'd0;
        cfg_wdata = 32'd0;
        cfg_apply = 1'b0;
        Load_IN   = 1'b0;
        Op_Sel    = 2'b00;
        A_in      = 24'sd0;
        B_in      = 24'sd0;
        op_cycle_count = 0;
        op_start_time = 0;
        op_end_time = 0;
        forced_lane_value = 6'd0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        program_config(1, 1, 3, 5, 7, 11, 13, 17);

        start_operation(10, 7, 2'b00);
        check_result(17, 0, 0, 1, 0, "ADD_10_7_BASELINE");

        start_operation(50, 200, 2'b01);
        check_result(-150, 0, 0, 1, 0, "SUB_50_200_BASELINE");

        start_operation(40, 40, 2'b10);
        check_result(445, 1, 0, 0, 0, "MUL_40_40_RANGE_ERROR");

        fork
            begin
                start_operation(10, 7, 2'b00);
            end
            begin
                inject_fault_before_corrector(4);
            end
        join
        check_result(17, 1, 1, 1, 0, "ADD_RED_FAULT_CORRECTED");
        release_faults();

        fork
            begin
                start_operation(10, 7, 2'b00);
            end
            begin
                inject_fault_before_corrector(2);
            end
        join
        check_result(17, 1, 1, 1, 0, "ADD_BASE_FAULT_CORRECTED");
        release_faults();

        program_config(1, 1, 5, 7, 11, 13, 17, 19);
        start_operation(200, 300, 2'b00);
        check_result(500, 0, 0, 1, 0, "ADD_200_300_RECONFIGURED");

        $display("[PASS] FINAL_ALU runtime RTL bench PASSED.");
        $finish;
    end

endmodule
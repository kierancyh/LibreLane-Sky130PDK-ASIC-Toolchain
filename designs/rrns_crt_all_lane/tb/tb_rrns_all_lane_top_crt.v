`timescale 1ns/1ps

module tb_rrns_all_lane_top_crt;

    reg clk;
    reg rst_n;

    reg         Start;
    reg  [1:0]  Op_Sel;
    reg  signed [15:0] A_in;
    reg  signed [15:0] B_in;

    wire        Done;
    wire signed [15:0] X_out;
    wire        Error_Detected;
    wire        Corrected;
    wire        Valid;

    integer tests_run;
    integer tests_failed;
    reg signed [3:0] force_r4_hold;
    reg signed [4:0] force_r5_hold;
    integer force_lane_hold;
    integer lane;

    rrns_all_lane_top_crt #(
        .WIDTH_IN (16),
        .M0(3), .M1(5), .M2(7), .M3(11), .M4(13), .M5(17),
        .W0(2), .W1(3), .W2(3), .W3(4), .W4(4), .W5(5)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .Start(Start),
        .Op_Sel(Op_Sel),
        .A_in(A_in),
        .B_in(B_in),
        .Done(Done),
        .X_out(X_out),
        .Error_Detected(Error_Detected),
        .Corrected(Corrected),
        .Valid(Valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("all_lane_crt_rtl_precheck.vcd");
        $dumpvars(0, tb_rrns_all_lane_top_crt);
    end

    task automatic pulse_start;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
    begin
        Op_Sel = op;
        A_in   = a;
        B_in   = b;

        @(negedge clk);
        Start = 1'b1;
        @(negedge clk);
        Start = 1'b0;
    end
    endtask

    task automatic wait_done_or_timeout;
        input [255:0] name;
        input integer max_cycles;
        output integer timed_out;
        integer cycles;
    begin
        timed_out = 0;
        cycles    = 0;

        while ((Done !== 1'b1) && (cycles < max_cycles)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (Done !== 1'b1) begin
            timed_out    = 1;
            tests_run    = tests_run + 1;
            tests_failed = tests_failed + 1;
            $display("[%0t] TEST %s | TIMEOUT waiting for Done after %0d cycles", $time, name, max_cycles);
            $display("  -> FAIL");
        end
    end
    endtask

    task automatic record_result;
        input [255:0]       name;
        input signed [15:0] expected_x;
        input               expected_err;
        input               expected_corr;
        input               expected_valid;
    begin
        tests_run = tests_run + 1;

        $display("[%0t] TEST %s | X_out=%0d exp=%0d err=%b exp_err=%b corr=%b exp_corr=%b valid=%b exp_valid=%b",
            $time, name, $signed(X_out), $signed(expected_x),
            Error_Detected, expected_err, Corrected, expected_corr, Valid, expected_valid);

        if (($signed(X_out) !== $signed(expected_x)) ||
            (Error_Detected !== expected_err) ||
            (Corrected !== expected_corr) ||
            (Valid !== expected_valid)) begin
            tests_failed = tests_failed + 1;
            $display("  -> FAIL");
        end else begin
            $display("  -> PASS");
        end

        @(negedge clk);
    end
    endtask

    task automatic run_test;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input               expected_err;
        input               expected_corr;
        input               expected_valid;
        input [255:0]       name;
        integer timed_out;
    begin
        pulse_start(op, a, b);
        wait_done_or_timeout(name, 60, timed_out);
        if (!timed_out) begin
            #1;
            record_result(name, expected_x, expected_err, expected_corr, expected_valid);
        end
    end
    endtask

    task automatic run_fault_test_red13;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input [255:0]       name;
        reg signed [3:0] corrupted_r4;
        integer timed_out;
    begin
        pulse_start(op, a, b);

        @(posedge dut.ALU_Done_all);
        #1;

        corrupted_r4 = dut.z_r4 + 1;
        force_r4_hold = corrupted_r4;
        force dut.z_r4 = force_r4_hold;

        wait_done_or_timeout(name, 60, timed_out);
        if (!timed_out) begin
            tests_run = tests_run + 1;
            $display("[%0t] TEST %s | X_out=%0d exp=%0d forced_r13=%0d err=%b corr=%b valid=%b",
                $time, name, $signed(X_out), $signed(expected_x), $signed(force_r4_hold),
                Error_Detected, Corrected, Valid);

            if (($signed(X_out) !== $signed(expected_x)) ||
                (Error_Detected !== 1'b1) ||
                (Corrected !== 1'b1) ||
                (Valid !== 1'b1)) begin
                tests_failed = tests_failed + 1;
                $display("  -> FAIL");
            end else begin
                $display("  -> PASS");
            end
        end

        release dut.z_r4;
        @(negedge clk);
    end
    endtask

    task automatic run_fault_test_red17;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input [255:0]       name;
        reg signed [4:0] corrupted_r5;
        integer timed_out;
    begin
        pulse_start(op, a, b);

        @(posedge dut.ALU_Done_all);
        #1;

        corrupted_r5 = dut.z_r5 + 1;
        force_r5_hold = corrupted_r5;
        force dut.z_r5 = force_r5_hold;

        wait_done_or_timeout(name, 60, timed_out);
        if (!timed_out) begin
            tests_run = tests_run + 1;
            $display("[%0t] TEST %s | X_out=%0d exp=%0d forced_r17=%0d err=%b corr=%b valid=%b",
                $time, name, $signed(X_out), $signed(expected_x), $signed(force_r5_hold),
                Error_Detected, Corrected, Valid);

            if (($signed(X_out) !== $signed(expected_x)) ||
                (Error_Detected !== 1'b1) ||
                (Corrected !== 1'b1) ||
                (Valid !== 1'b1)) begin
                tests_failed = tests_failed + 1;
                $display("  -> FAIL");
            end else begin
                $display("  -> PASS");
            end
        end

        release dut.z_r5;
        @(negedge clk);
    end
    endtask

    task automatic run_fault_test_base_lane;
        input integer       lane_idx;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input [255:0]       name;
        integer original_lane;
        integer corrupted_lane;
        integer timed_out;
    begin
        pulse_start(op, a, b);

        @(posedge dut.ALU_Done_all);
        #1;

        case (lane_idx)
            0: begin
                original_lane  = dut.z_r0;
                corrupted_lane = (original_lane != 0) ? 0 : 1;
                force_lane_hold = corrupted_lane;
                force dut.z_r0 = force_lane_hold;
            end
            1: begin
                original_lane  = dut.z_r1;
                corrupted_lane = (original_lane != 0) ? 0 : 1;
                force_lane_hold = corrupted_lane;
                force dut.z_r1 = force_lane_hold;
            end
            2: begin
                original_lane  = dut.z_r2;
                corrupted_lane = (original_lane != 0) ? 0 : 1;
                force_lane_hold = corrupted_lane;
                force dut.z_r2 = force_lane_hold;
            end
            default: begin
                original_lane  = dut.z_r3;
                corrupted_lane = (original_lane != 0) ? 0 : 1;
                force_lane_hold = corrupted_lane;
                force dut.z_r3 = force_lane_hold;
            end
        endcase

        wait_done_or_timeout(name, 60, timed_out);
        if (!timed_out) begin
            tests_run = tests_run + 1;
            $display("[%0t] TEST %s | lane=%0d X_out=%0d exp=%0d orig_lane=%0d forced_lane=%0d err=%b corr=%b valid=%b",
                $time, name, lane_idx, $signed(X_out), $signed(expected_x),
                original_lane, force_lane_hold, Error_Detected, Corrected, Valid);

            if (($signed(X_out) !== $signed(expected_x)) ||
                (Error_Detected !== 1'b1) ||
                (Corrected !== 1'b1) ||
                (Valid !== 1'b1)) begin
                tests_failed = tests_failed + 1;
                $display("  -> FAIL");
            end else begin
                $display("  -> PASS");
            end
        end

        case (lane_idx)
            0: release dut.z_r0;
            1: release dut.z_r1;
            2: release dut.z_r2;
            default: release dut.z_r3;
        endcase

        @(negedge clk);
    end
    endtask

    task automatic finish_report;
        input [255:0] banner;
    begin
        $display("%s", banner);
        $display("[CRT RTL] SUMMARY | total=%0d failed=%0d passed=%0d", tests_run, tests_failed, tests_run - tests_failed);
        #20;
        if (tests_failed != 0)
            $fatal(1, "CRT RTL bench had %0d failing tests", tests_failed);
        else
            $finish;
    end
    endtask

    initial begin
        Start        = 1'b0;
        Op_Sel       = 2'b00;
        A_in         = 16'd0;
        B_in         = 16'd0;
        tests_run    = 0;
        tests_failed = 0;

        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Clean valid cases
        run_test(2'b00, 16'd10,   16'd7,     16'd17,    1'b0, 1'b0, 1'b1, "ADD_10_7");
        run_test(2'b00, 16'd123,  16'd321,   16'd444,   1'b0, 1'b0, 1'b1, "ADD_123_321");
        run_test(2'b01, 16'd200,  16'd50,    16'd150,   1'b0, 1'b0, 1'b1, "SUB_200_50");
        run_test(2'b01, 16'd400,  16'd123,   16'd277,   1'b0, 1'b0, 1'b1, "SUB_400_123");
        run_test(2'b01, 16'sd50,  16'sd200, -16'sd150,  1'b0, 1'b0, 1'b1, "SUB_WRAP");
        run_test(2'b01, 16'sd123, 16'sd400, -16'sd277,  1'b0, 1'b0, 1'b1, "SUB_NEG_123_400");
        run_test(2'b10, 16'd11,   16'd17,    16'd187,   1'b0, 1'b0, 1'b1, "MUL_11_17");
        run_test(2'b10, 16'd14,   16'd20,    16'd280,   1'b0, 1'b0, 1'b1, "MUL_14_20");
        run_test(2'b10, 16'd9,    16'd21,    16'd189,   1'b0, 1'b0, 1'b1, "MUL_9_21");

        // Overflow / out-of-range should be invalid, not corrected
        run_test(2'b00, 16'd1000, 16'd300,   16'd145,   1'b1, 1'b0, 1'b0, "ADD_WRAP_INVALID");
        run_test(2'b10, 16'd40,   16'd40,    16'd445,   1'b1, 1'b0, 1'b0, "MUL_WRAP_INVALID");

        // Single redundant-lane faults
        run_fault_test_red13(2'b00, 16'd10,   16'd7,    16'd17,  "ADD_RED13_FAULT");
        run_fault_test_red13(2'b10, 16'd14,   16'd20,   16'd280, "MUL_RED13_FAULT");
        run_fault_test_red17(2'b01, 16'd200,  16'd50,   16'd150, "SUB_RED17_FAULT");
        run_fault_test_red17(2'b00, 16'd123,  16'd321,  16'd444, "ADD_RED17_FAULT");

        // Single base-lane faults: experimental any-lane correction.
        for (lane = 0; lane < 4; lane = lane + 1) begin
            run_fault_test_base_lane(lane, 2'b00, 16'd10,   16'd7,     16'd17,   "ADD_BASE_FAULT_CORR");
            run_fault_test_base_lane(lane, 2'b00, 16'd123,  16'd321,   16'd444,  "ADD2_BASE_FAULT_CORR");
            run_fault_test_base_lane(lane, 2'b01, 16'd400,  16'd123,   16'd277,  "SUB_BASE_FAULT_CORR");
            run_fault_test_base_lane(lane, 2'b01, 16'sd123, 16'sd400, -16'sd277, "SUB_NEG_BASE_FAULT_CORR");
            run_fault_test_base_lane(lane, 2'b10, 16'd11,   16'd17,    16'd187,  "MUL_BASE_FAULT_CORR");
            run_fault_test_base_lane(lane, 2'b10, 16'd14,   16'd20,    16'd280,  "MUL2_BASE_FAULT_CORR");
        end

        finish_report("CRT RRNS correction-stage tests completed.");
    end

endmodule

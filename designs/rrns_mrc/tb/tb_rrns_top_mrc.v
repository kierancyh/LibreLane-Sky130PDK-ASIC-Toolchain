`timescale 1ns/1ps

module tb_rrns_top_mrc;

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

    rrns_top_mrc #(
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
        $dumpfile("mrc_rtl_precheck.vcd");
        $dumpvars(0, tb_rrns_top_mrc);
    end

    task run_test;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input               expected_err;
        input               expected_corr;
        input               expected_valid;
        input [255:0]       name;
    begin
        Op_Sel = op;
        A_in   = a;
        B_in   = b;

        @(negedge clk);
        Start = 1'b1;
        @(negedge clk);
        Start = 1'b0;

        @(posedge Done);
        #1;

        $display("[%0t] TEST %s | X_out=%0d exp=%0d err=%b exp_err=%b corr=%b exp_corr=%b valid=%b exp_valid=%b",
            $time, name, $signed(X_out), $signed(expected_x),
            Error_Detected, expected_err, Corrected, expected_corr, Valid, expected_valid);

        if (($signed(X_out) !== $signed(expected_x)) ||
            (Error_Detected !== expected_err) ||
            (Corrected !== expected_corr) ||
            (Valid !== expected_valid))
            $display("  -> FAIL");
        else
            $display("  -> PASS");

        @(negedge clk);
    end
    endtask

    task run_fault_test_red13;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input [255:0]       name;
        reg signed [3:0] corrupted_r4;
    begin
        Op_Sel = op; A_in = a; B_in = b;

        @(negedge clk); Start = 1'b1;
        @(negedge clk); Start = 1'b0;

        @(posedge dut.ALU_Done_all);
        #1;

        corrupted_r4 = dut.z_r4 + 1;
        force dut.z_r4 = corrupted_r4;

        @(posedge Done);
        #1;

        $display("[%0t] TEST %s | X_out=%0d exp=%0d forced_r13=%0d err=%b corr=%b valid=%b",
            $time, name, $signed(X_out), $signed(expected_x), $signed(corrupted_r4),
            Error_Detected, Corrected, Valid);

        if (($signed(X_out) !== $signed(expected_x)) ||
            (Error_Detected !== 1'b1) ||
            (Corrected !== 1'b1) ||
            (Valid !== 1'b1))
            $display("  -> FAIL");
        else
            $display("  -> PASS");

        release dut.z_r4;
        @(negedge clk);
    end
    endtask

    task run_fault_test_red17;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input [255:0]       name;
        reg signed [4:0] corrupted_r5;
    begin
        Op_Sel = op; A_in = a; B_in = b;

        @(negedge clk); Start = 1'b1;
        @(negedge clk); Start = 1'b0;

        @(posedge dut.ALU_Done_all);
        #1;

        corrupted_r5 = dut.z_r5 + 1;
        force dut.z_r5 = corrupted_r5;

        @(posedge Done);
        #1;

        $display("[%0t] TEST %s | X_out=%0d exp=%0d forced_r17=%0d err=%b corr=%b valid=%b",
            $time, name, $signed(X_out), $signed(expected_x), $signed(corrupted_r5),
            Error_Detected, Corrected, Valid);

        if (($signed(X_out) !== $signed(expected_x)) ||
            (Error_Detected !== 1'b1) ||
            (Corrected !== 1'b1) ||
            (Valid !== 1'b1))
            $display("  -> FAIL");
        else
            $display("  -> PASS");

        release dut.z_r5;
        @(negedge clk);
    end
    endtask

    task run_fault_test_base_lane;
        input [1:0]         op;
        input signed [15:0] a;
        input signed [15:0] b;
        input signed [15:0] expected_x;
        input [255:0]       name;
        reg signed [3:0] original_r3;
        reg signed [3:0] corrupted_r3;
    begin
        Op_Sel = op; A_in = a; B_in = b;

        @(negedge clk); Start = 1'b1;
        @(negedge clk); Start = 1'b0;

        @(posedge dut.ALU_Done_all);
        #1;

        original_r3  = dut.z_r3;
        corrupted_r3 = (original_r3 != 0) ? 0 : 1;
        force dut.z_r3 = corrupted_r3;

        @(posedge Done);
        #1;

        $display("[%0t] TEST %s | X_out=%0d exp=%0d orig_r3=%0d forced_r3=%0d err=%b corr=%b valid=%b",
            $time, name, $signed(X_out), $signed(expected_x),
            $signed(original_r3), $signed(corrupted_r3),
            Error_Detected, Corrected, Valid);

        if (($signed(X_out) !== $signed(expected_x)) ||
            (Error_Detected !== 1'b1) ||
            (Corrected !== 1'b1) ||
            (Valid !== 1'b1))
            $display("  -> FAIL");
        else
            $display("  -> PASS");

        release dut.z_r3;
        @(negedge clk);
    end
    endtask

    initial begin
        Start  = 1'b0;
        Op_Sel = 2'b00;
        A_in   = 16'd0;
        B_in   = 16'd0;

        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Clean valid cases
        run_test(2'b00, 16'd10,   16'd7,     16'd17,    1'b0, 1'b0, 1'b1, "MRC_ADD_10_7");
        run_test(2'b00, 16'd123,  16'd321,   16'd444,   1'b0, 1'b0, 1'b1, "MRC_ADD_123_321");
        run_test(2'b01, 16'd200,  16'd50,    16'd150,   1'b0, 1'b0, 1'b1, "MRC_SUB_200_50");
        run_test(2'b01, 16'd400,  16'd123,   16'd277,   1'b0, 1'b0, 1'b1, "MRC_SUB_400_123");
        run_test(2'b01, 16'sd50,  16'sd200, -16'sd150,  1'b0, 1'b0, 1'b1, "MRC_SUB_WRAP");
        run_test(2'b01, 16'sd123, 16'sd400, -16'sd277,  1'b0, 1'b0, 1'b1, "MRC_SUB_NEG_123_400");
        run_test(2'b10, 16'd11,   16'd17,    16'd187,   1'b0, 1'b0, 1'b1, "MRC_MUL_11_17");
        run_test(2'b10, 16'd14,   16'd20,    16'd280,   1'b0, 1'b0, 1'b1, "MRC_MUL_14_20");
        run_test(2'b10, 16'd9,    16'd21,    16'd189,   1'b0, 1'b0, 1'b1, "MRC_MUL_9_21");

        // Overflow / out-of-range should be invalid, not corrected
        run_test(2'b00, 16'd1000, 16'd300,   16'd145,   1'b1, 1'b0, 1'b0, "MRC_ADD_WRAP_INVALID");
        run_test(2'b10, 16'd40,   16'd40,    16'd445,   1'b1, 1'b0, 1'b0, "MRC_MUL_WRAP_INVALID");

        // Single redundant-lane faults
        run_fault_test_red13(2'b00, 16'd10,   16'd7,    16'd17,  "MRC_ADD_RED13_FAULT");
        run_fault_test_red13(2'b10, 16'd14,   16'd20,   16'd280, "MRC_MUL_RED13_FAULT");
        run_fault_test_red17(2'b01, 16'd200,  16'd50,   16'd150, "MRC_SUB_RED17_FAULT");
        run_fault_test_red17(2'b00, 16'd123,  16'd321,  16'd444, "MRC_ADD_RED17_FAULT");

        // Single base-lane faults: should correct back to clean result
        run_fault_test_base_lane(2'b00, 16'd10,   16'd7,    16'd17,  "MRC_ADD_BASE_FAULT_CORR");
        run_fault_test_base_lane(2'b00, 16'd123,  16'd321,  16'd444, "MRC_ADD2_BASE_FAULT_CORR");
        run_fault_test_base_lane(2'b01, 16'd400,  16'd123,  16'd277, "MRC_SUB_BASE_FAULT_CORR");
        run_fault_test_base_lane(2'b01, 16'sd123, 16'sd400, -16'sd277, "MRC_SUB_NEG_BASE_FAULT_CORR");
        run_fault_test_base_lane(2'b10, 16'd11,   16'd17,   16'd187, "MRC_MUL_BASE_FAULT_CORR");
        run_fault_test_base_lane(2'b10, 16'd14,   16'd20,   16'd280, "MRC_MUL2_BASE_FAULT_CORR");

        $display("MRC RRNS correction-stage tests completed.");
        #20;
        $finish;
    end

endmodule

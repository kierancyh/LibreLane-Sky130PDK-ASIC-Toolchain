`timescale 1ns/1ps

module tb_rns_top_mrc;

    // Clock & Reset
    reg clk;
    reg rst_n;

    // DUT interface signals
    reg         Start;
    reg  [1:0]  Op_Sel;       // 00=ADD, 01=SUB, 10=MUL
    reg  [15:0] A_in;
    reg  [15:0] B_in;

    wire        Done;
    wire [15:0] X_out;

    // Instantiate MRC DUT
    rns_top_mrc #(
        .WIDTH_IN (16),
        .M0       (3),
        .M1       (5),
        .M2       (7),
        .M3       (11),
        .W0       (2),
        .W1       (3),
        .W2       (3),
        .W3       (4)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .Start (Start),
        .Op_Sel(Op_Sel),
        .A_in  (A_in),
        .B_in  (B_in),
        .Done  (Done),
        .X_out (X_out)
    );

    // Clock generation: 100 MHz (10 ns period)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // VCD dump for workflow precheck / Surfer
    initial begin
        $dumpfile("rtl_precheck.vcd");
        $dumpvars(0, tb_rns_top_mrc);
    end

    // Task: run one ALU operation
    // op       : 00=ADD, 01=SUB, 10=MUL
    // a, b     : operands
    // expected : expected result mod 1155
    // name     : test name for printing
    task run_test;
        input [1:0]   op;
        input [15:0]  a;
        input [15:0]  b;
        input [15:0]  expected;
        input [127:0] name;
    begin
        Op_Sel = op;
        A_in   = a;
        B_in   = b;

        // Pulse Start for one clock cycle
        @(negedge clk);
        Start = 1'b1;
        @(negedge clk);
        Start = 1'b0;

        // Wait for completion
        @(posedge Done);
        #1;

        $display("[%0t] TEST %s | MRC | op=%b, A=%0d, B=%0d, X_out=%0d, expected=%0d",
                 $time, name, op, a, b, X_out, expected);

        if (X_out !== expected) begin
            $display("  -> FAIL");
        end else begin
            $display("  -> PASS");
        end

        @(negedge clk);
    end
    endtask

    // Reset and stimulus
    initial begin
        Start  = 1'b0;
        Op_Sel = 2'b00;
        A_in   = 16'd0;
        B_in   = 16'd0;

        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // ADD
        run_test(2'b00, 16'd10,   16'd7,   16'd17,   "ADD_10_7");
        run_test(2'b00, 16'd1000, 16'd300, 16'd145,  "ADD_WRAP");

        // SUB
        run_test(2'b01, 16'd200,  16'd50,  16'd150,  "SUB_200_50");
        run_test(2'b01, 16'd50,   16'd200, 16'd1005, "SUB_WRAP");

        // MUL
        run_test(2'b10, 16'd11,   16'd17,  16'd187,  "MUL_11_17");
        run_test(2'b10, 16'd40,   16'd40,  16'd445,  "MUL_WRAP");

        $display("All MRC tests completed.");
        #20;
        $finish;
    end

endmodule
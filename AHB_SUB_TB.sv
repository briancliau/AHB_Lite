`timescale 1ns/1ps
import AHB_pkg::*;
//======================================================================
// Stage 2 unit testbench for AHB_dutordinate.
//
// DRIVING DISCIPLINE
//   Every DUT input is changed 1 ns AFTER a clock edge, never on it.
//   Real simulation time between the edge and the change removes any
//   dependence on scheduling-region order, so this behaves identically
//   in Verilator, VCS, Questa and Xcelium.
//======================================================================
module AHB_SUB_TB ();

    logic        HCLK;
    logic        HRESETn;
    logic        HSELx;
    logic        HREADY;
    logic        HWRITE;
    logic [31:0] HADDR;
    logic [2:0]  HSIZE;
    logic [1:0]  HTRANS;
    logic [31:0] HWDATA;
    logic        HRESP;
    logic        HREADYOUT;
    logic [31:0] HRDATA;

    int errors = 0;

    AHB_subordinate #(ADDR_BITS[0]) dut
    (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSELx     (HSELx),
        .HREADY    (HREADY),
        .HWRITE    (HWRITE),
        .HADDR     (HADDR),
        .HSIZE     (HSIZE),
        .HTRANS    (HTRANS),
        .HWDATA    (HWDATA),
        .HRESP     (HRESP),
        .HREADYOUT (HREADYOUT),
        .HRDATA    (HRDATA)
    );

    // 100 MHz
    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    initial begin
        #2000;
        $display("ERROR: simulation timed out");
        $finish;
    end

    // Advance one clock and land 1 ns past the edge, where it is safe to
    // change DUT inputs.
    task automatic step();
        @(posedge HCLK);
        #1;
    endtask

    // Advance one clock, then check dataphase_valid past every
    // scheduling region.
    task automatic step_check(input logic exp, input string msg);
        @(posedge HCLK);
        #1;
        if (dut.dataphase_valid !== exp) begin
            errors++;
            $display("FAIL @ %0t: %s (expected %0b, got %0b)",
                     $time, msg, exp, dut.dataphase_valid);
        end
    endtask

    task automatic step_check_data(input logic [31:0] exp, input string msg);
        @(posedge HCLK);
        #1
        if (HRDATA !== exp) begin
            errors++;
            $display("FAIL @ %0t: %s (expected %08h, got %08h)", $time, msg, exp, HRDATA);
        end
    endtask

    task automatic step_write_data(input logic [31:0] write_data, input logic [31:0] exp, input string msg);
        @(negedge HCLK);
        HWRITE = 1'b1;
        HWDATA = write_data;

        @(posedge HCLK);
        #1;
        HWRITE = 1'b0;

        @(posedge HCLK);
        #1
        if (HRDATA !== exp) begin
            errors++;
            $display("FAIL @ %0t: %s (expected %08h, got %08h)", $time, msg, exp, HRDATA);
        end
    endtask

    initial begin
        // Time 0. Blocking is correct here: there is no edge to race.
        HRESETn = 1'b0;
        HSELx   = 1'b0;
        HREADY  = 1'b1;
        HWRITE  = 1'b0;
        HADDR   = '0;
        HSIZE   = 3'b010;   // word
        HTRANS  = 2'b00;    // IDLE
        HWDATA  = '0;

        step();
        step();
        HRESETn = 1'b1;     // deassert away from the clock edge
        step();

        dut.mem[0] = 8'hEF;
        dut.mem[1] = 8'hBE;
        dut.mem[2] = 8'hAD;
        dut.mem[3] = 8'hDE;

        dut.mem[32] = 8'h78;
        dut.mem[33] = 8'h56;
        dut.mem[34] = 8'h34;
        dut.mem[35] = 8'h12;

        //-------------- TEST 1: idle rejection --------------------------
        $display("--- TEST 1: idle rejection ---");
        HSELx  = 1'b1;
        HTRANS = 2'b00;
        HREADY = 1'b1;
        repeat (10) step_check(1'b0, "IDLE must not start a data phase");

        //-------------- TEST 2: three back-to-back NONSEQ ---------------
        $display("--- TEST 2: back-to-back NONSEQ ---");
        step();                                          // edge A
        HTRANS = 2'b10;                                  // NONSEQ live from A+1

        step_check(1'b1, "transfer 1 data phase");       // edge B
        
        step_check(1'b1, "transfer 2 data phase");       // edge C
        
        step_check(1'b1, "transfer 3 data phase");       // edge D
        
        HTRANS = 2'b00;                                  // IDLE from D+1

        step_check(1'b0, "data phase must end");         // edge E


        //-------------- TEST 3: HREADY freeze ---------------------------
        $display("--- TEST 3: HREADY freeze ---");
        step();                                          // edge F, quiet
        HTRANS = 2'b10;                                  // one transfer

        step_check(1'b1, "data phase started");          // edge G
        HTRANS = 2'b00;     // manager goes idle
        HREADY = 1'b0;      // ANOTHER dutordinate stalls the shared bus

        step_check(1'b1, "stall cycle 1 must hold");     // edge H
        step_check(1'b1, "stall cycle 2 must hold");     // edge I
        HREADY = 1'b1;      // bus resumes

        step_check(1'b0, "data phase ends after stall"); // edge J

        //-------------- TEST 4: HRDATA read -----------------------------
        HREADY = 1'b1;
        HTRANS = 2'b10;
        HWRITE = 1'b0;
        
        $display("--- TEST 4: HRDATA Read ---");
        HADDR = 32'h0000_0ABC;
        step_check_data(32'b0, "read 1 data phase");
        HADDR = 32'h0000_0020;
        step_check_data(32'h12345678, "read 1 data phase 0x0024");
        HADDR = 32'h0000_0000;
        step_check_data(32'hDEADBEEF, "read 1 data phase 0x0000");

        //-------------- TEST 4: HWDATA write -----------------------------
        HREADY = 1'b1;
        HTRANS = 2'b10;

        $display("--- TEST 5: HWDATA Write ---");
        //-------------- WORD WRITE ---------------------------------------
        HSIZE = 3'b010;
        HADDR = 32'h0000_010;
        step_write_data(32'h87654321, 32'h87654321, "write word data at 0x1000");
        HSIZE = 3'b010;
        HADDR = 32'h0000_0000;
        step_write_data(32'h00000000, 32'h00000000, "write word data at 0x0000");

        //-------------- HALFWORD WRITE -----------------------------------
        HSIZE = 3'b001;
        HADDR = 32'h0000_0202;
        step_write_data(32'hAAAABBBB, 32'hAAAA0000, "write halfword data at 0x0202");
        HSIZE = 3'b001;
        HADDR = 32'h0000_0200;
        step_write_data(32'hCCCCDDDD, 32'hAAAADDDD, "write halfword data at 0x0200");

        //-------------- BYTE WRITE ---------------------------------------
        HSIZE = 3'b000;
        HADDR = 32'h0000_0300;
        step_write_data(32'h11223344, 32'h00000044, "write byte data at 0x0300");
        HSIZE = 3'b000;
        HADDR = 32'h0000_0301;
        step_write_data(32'hAABBCCDD, 32'h0000CC44, "write byte data at 0x0301");
        HSIZE = 3'b000;
        HADDR = 32'h0000_0302;
        step_write_data(32'h99887766, 32'h0088CC44, "write byte data at 0x0302");
        HSIZE = 3'b000;
        HADDR = 32'h0000_0303;
        step_write_data(32'hFFEEDDCC, 32'hFF88CC44, "write byte data at 0x0303");


        //-------------- summary -----------------------------------------
        HSELx = 1'b0;
        step();
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $finish;
    end

    initial begin
        $dumpfile("AHB_dut_TB.vcd");
        $dumpvars(0, AHB_dut_TB);
    end

endmodule
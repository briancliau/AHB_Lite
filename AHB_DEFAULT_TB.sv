`timescale 1ns/1ps
//======================================================================
// I5a unit testbench: AHB_default_subordinate, standalone.
//
// THE HREADY LOOP
//   In the real system HREADY comes back from the interconnect mux. When
//   this module owns the data phase, the mux is routing ITS HREADYOUT, so
//   HREADY == HREADYOUT. When it owns nothing, HREADYOUT is 1 and the mux
//   default is also 1 -- they still agree. So on a bus where this is the
//   only subordinate, tying HREADY = HREADYOUT is a faithful model.
//
//   This matters: closing the loop is what makes TEST 4 and TEST 5 real.
//   If error_second sat inside the "else if (HREADY)" enable, this module
//   would freeze its own enable while stalling and the bus would hang
//   forever. With HREADY forced high from outside, that bug is invisible.
//
//   TEST 6 overrides the loop to simulate a DIFFERENT subordinate stalling.
//======================================================================
module AHB_DEFAULT_TB;

    logic        HCLK;
    logic        HRESETn;
    logic        HSELx;
    logic        HREADY;
    logic [1:0]  HTRANS;
    logic        HREADYOUT;
    logic        HRESP;
    logic [31:0] HRDATA;

    // Loop override, used only by TEST 6.
    logic        force_ready_en;
    logic        force_ready_val;

    int errors = 0;

    assign HREADY = force_ready_en ? force_ready_val : HREADYOUT;

    AHB_default_subordinate dut (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSELx     (HSELx),
        .HREADY    (HREADY),
        .HTRANS    (HTRANS),
        .HREADYOUT (HREADYOUT),
        .HRESP     (HRESP),
        .HRDATA    (HRDATA)
    );

    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    initial begin
        #3000;
        $display("ERROR: simulation timed out");
        $finish;
    end

    task automatic step();
        @(negedge HCLK);
    endtask

    // Check the (HRESP, HREADYOUT) pair. !== catches X as well as 0/1.
    task automatic chk(input logic exp_resp, input logic exp_ready, input string msg);
        if (HRESP !== exp_resp || HREADYOUT !== exp_ready) begin
            errors++;
            $display("FAIL @ %0t: %s  expected (HRESP,HREADYOUT)=(%b,%b), got (%b,%b)",
                     $time, msg, exp_resp, exp_ready, HRESP, HREADYOUT);
        end
    endtask

    //==================================================================
    // Background invariants -- run during every test.
    //==================================================================
    int stall_run = 0;

    always @(negedge HCLK) begin
        if (HRESETn) begin
            // A two-cycle ERROR stalls for exactly ONE cycle. More than
            // that means the sequence cannot terminate. This reports the
            // deadlock directly instead of leaving you to read a timeout.
            if (!HREADYOUT) stall_run = stall_run + 1;
            else            stall_run = 0;
            if (stall_run == 2) begin
                errors++;
                $display("FAIL @ %0t: HREADYOUT low 2 cycles running -- sequence cannot end",
                         $time);
            end

            // This module only ever stalls to deliver an ERROR.
            if (!HREADYOUT && HRESP !== 1'b1) begin
                errors++;
                $display("FAIL @ %0t: stalled with HRESP=%b, expected ERROR", $time, HRESP);
            end

            if (HRDATA !== 32'h0) begin
                errors++;
                $display("FAIL @ %0t: HRDATA=%08h, expected 0", $time, HRDATA);
            end
        end
    end

    //==================================================================
    // Stimulus
    //==================================================================
    initial begin
        HRESETn         = 1'b0;
        HSELx           = 1'b0;
        HTRANS          = AHB_pkg::IDLE;
        force_ready_en  = 1'b0;
        force_ready_val = 1'b1;

        step();
        step();
        HRESETn = 1'b1;

        //---------------- TEST 1: reset state ---------------------------
        $display("--- TEST 1: reset state ---");
        step();
        chk(1'b0, 1'b1, "T1 reset");
        if (dut.dataphase_valid !== 1'b0 || dut.error_second !== 1'b0) begin
            errors++;
            $display("FAIL: reset left dv=%b es=%b", dut.dataphase_valid, dut.error_second);
        end

        //---------------- TEST 2: IDLE never stalls ---------------------
        // HTRANS[1] = 0 for IDLE, so addr_accept stays low even though
        // this module is selected.
        $display("--- TEST 2: selected + IDLE ---");
        HSELx  = 1'b1;
        HTRANS = AHB_pkg::IDLE;
        repeat (10) begin
            step();
            chk(1'b0, 1'b1, "T2 IDLE must not respond");
        end

        //---------------- TEST 3: BUSY never stalls ---------------------
        // HTRANS[1] = 0 for BUSY too. One bit rejects both.
        $display("--- TEST 3: selected + BUSY ---");
        HTRANS = AHB_pkg::BUSY;
        repeat (10) begin
            step();
            chk(1'b0, 1'b1, "T3 BUSY must not respond");
        end

        //---------------- TEST 4: one two-cycle ERROR -------------------
        $display("--- TEST 4: single two-cycle ERROR ---");
        HTRANS = AHB_pkg::IDLE;
        step();
        chk(1'b0, 1'b1, "T4 quiet before");

        HTRANS = AHB_pkg::NONSEQ;        // one unmapped transfer

        step(); chk(1'b1, 1'b0, "T4 ERROR cycle 1");
                HTRANS = AHB_pkg::IDLE;  // manager cancels its next transfer

        step(); chk(1'b1, 1'b1, "T4 ERROR cycle 2");
        step(); chk(1'b0, 1'b1, "T4 back to idle");
        step(); chk(1'b0, 1'b1, "T4 stays idle");

        //---------------- TEST 5: two ERRORs back to back ---------------
        // The manager holds NONSEQ, so a new transfer is accepted on the
        // edge that ends ERROR cycle 2. Expect two COMPLETE sequences --
        // this is the test that fails if error_second latches instead of
        // pulsing.
        $display("--- TEST 5: back-to-back ERRORs ---");
        HTRANS = AHB_pkg::NONSEQ;

        step(); chk(1'b1, 1'b0, "T5 xfer1 ERROR cycle 1");
        step(); chk(1'b1, 1'b1, "T5 xfer1 ERROR cycle 2");
        step(); chk(1'b1, 1'b0, "T5 xfer2 ERROR cycle 1");
        step(); chk(1'b1, 1'b1, "T5 xfer2 ERROR cycle 2");
                HTRANS = AHB_pkg::IDLE;
        step(); chk(1'b0, 1'b1, "T5 back to idle");

        //---------------- TEST 6: another subordinate stalling ----------
        // Not selected, and the bus is held by someone else. This module
        // must never stall a transfer it is not part of.
        $display("--- TEST 6: unselected while the bus is stalled ---");
        HSELx           = 1'b0;
        HTRANS          = AHB_pkg::NONSEQ;   // addressed to a mapped region
        force_ready_en  = 1'b1;
        force_ready_val = 1'b0;              // someone else stalls

        repeat (5) begin
            step();
            chk(1'b0, 1'b1, "T6 must not stall a foreign transfer");
        end

        force_ready_en = 1'b0;               // restore the loop
        HTRANS         = AHB_pkg::IDLE;
        step();
        chk(1'b0, 1'b1, "T6 clean after release");

        //---------------- summary ---------------------------------------
        step();
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $finish;
    end

    initial begin
        $dumpfile("AHB_DEFAULT_TB.vcd");
        $dumpvars(0, AHB_DEFAULT_TB);
    end

endmodule
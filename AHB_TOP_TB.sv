`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_TOP_TB; 
    logic        HCLK;
    logic        HRESETn;
    logic [31:0] HADDR;
    logic [1:0]  HTRANS;
    logic        HWRITE;
    logic [2:0]  HSIZE;
    logic [31:0] HWDATA;
    logic [31:0] HRDATA;
    logic        HRESP;
    logic        HREADY;
 
    int errors = 0;
 
    AHB_top dut (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),
        .HADDR   (HADDR),
        .HTRANS  (HTRANS),
        .HWRITE  (HWRITE),
        .HSIZE   (HSIZE),
        .HWDATA  (HWDATA),
        .HRDATA  (HRDATA),
        .HRESP   (HRESP),
        .HREADY  (HREADY)
    );
 
    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end
 
    initial begin
        #100000;
        $display("ERROR: simulation timed out");
        $finish;
    end
 
    task automatic step();
        @(negedge HCLK);
    endtask
 
    task automatic fail(input string msg);
        errors++;
        $display("FAIL @ %0t: %s", $time, msg);
    endtask
 
    //==================================================================
    // Per-instance parameter check.
    //
    // The elaboration $error checks in AHB_top verify the memory MAP, but
    // they cannot detect a wrong ADDR_BITS reaching an instance. This can:
    // it reads the actual array depth each subordinate was built with.
    //
    // Without this, the aliasing test below is ambiguous -- a manager that
    // drives HWDATA a cycle early and a subordinate that aliases produce
    // identical failure text.
    //==================================================================
    task automatic check_params();
        if ($size(dut.sub_gen[0].subordinate.mem) != 32'h1000)
            fail($sformatf("sub0 mem depth %0d, expected 4096",
                           $size(dut.sub_gen[0].subordinate.mem)));
        if ($size(dut.sub_gen[1].subordinate.mem) != 32'h2000)
            fail($sformatf("sub1 mem depth %0d, expected 8192",
                           $size(dut.sub_gen[1].subordinate.mem)));
        if ($size(dut.sub_gen[2].subordinate.mem) != 32'h4000)
            fail($sformatf("sub2 mem depth %0d, expected 16384",
                           $size(dut.sub_gen[2].subordinate.mem)));
    endtask
 
    task automatic setup_mem();
        // sub 0, offset 0x000 -> 0xDEADBEEF
        dut.sub_gen[0].subordinate.mem[3]   = 8'hDE;
        dut.sub_gen[0].subordinate.mem[2]   = 8'hAD;
        dut.sub_gen[0].subordinate.mem[1]   = 8'hBE;
        dut.sub_gen[0].subordinate.mem[0]   = 8'hEF;
        // sub 1, offset 0x020 -> 0xAABBCCDD
        dut.sub_gen[1].subordinate.mem[35]  = 8'hAA;
        dut.sub_gen[1].subordinate.mem[34]  = 8'hBB;
        dut.sub_gen[1].subordinate.mem[33]  = 8'hCC;
        dut.sub_gen[1].subordinate.mem[32]  = 8'hDD;
        // sub 2, offset 0x100 -> 0x11223344
        dut.sub_gen[2].subordinate.mem[259] = 8'h11;
        dut.sub_gen[2].subordinate.mem[258] = 8'h22;
        dut.sub_gen[2].subordinate.mem[257] = 8'h33;
        dut.sub_gen[2].subordinate.mem[256] = 8'h44;
    endtask
 
    //==================================================================
    // Bus helpers. HTRANS is NONSEQ for the address phase and IDLE
    // thereafter, so each call issues exactly one transfer.
    //==================================================================
    task automatic read_bus(input logic [31:0] addr,
                            input logic [2:0]  size,
                            input logic [31:0] exp_data,
                            input logic        exp_resp,
                            input logic        exp_ready,
                            input string       msg);
        int stalls = 0;
        int exp_waits_idx;

        @(negedge HCLK);
        HADDR  = addr;
        HTRANS = NONSEQ;
        HSIZE  = size;
        HWRITE = 1'b0;
        while (HREADY !== 1'b1) @(negedge HCLK);
        exp_waits_idx = 0;
        for (int i = 0; i < NUM_SUBORDINATES; i++) begin
            if (HADDR >= BASE_ADDR[i] && HADDR < (BASE_ADDR[i] + ADDR_SIZE[i])) begin
                exp_waits_idx = i;
            end
        end
 
        @(negedge HCLK);          // data phase
        HTRANS = IDLE;
        while (HREADY !== 1'b1) begin
            stalls++;
            @(negedge HCLK);
        end
        if (stalls !== WAIT_STATES[exp_waits_idx])
            fail($sformatf("%s: %0d wait states, expected %0d", msg, stalls, WAIT_STATES[exp_waits_idx]));
        if (HRDATA !== exp_data || HRESP !== exp_resp || HREADY !== exp_ready) begin
            errors++;
            $display("FAIL @ %0t: %s", $time, msg);
            if (HRDATA !== exp_data)
                $display("  -> HRDATA expected %08h, got %08h", exp_data, HRDATA);
            if (HRESP !== exp_resp)
                $display("  -> HRESP  expected %0b, got %0b", exp_resp, HRESP);
            if (HREADY !== exp_ready)
                $display("  -> HREADY expected %0b, got %0b", exp_ready, HREADY);
        end
    endtask
 
    // HWDATA is a DATA-PHASE signal: driven at the second negedge, one
    // cycle after HADDR. Driving it alongside HADDR makes two consecutive
    // writes clobber each other.
    task automatic write_bus(input logic [31:0] addr,
                             input logic [2:0]  size,
                             input logic [31:0] write_data,
                             input logic        exp_resp,
                             input logic        exp_ready,
                             input string       msg);
        @(negedge HCLK);
        HADDR  = addr;
        HTRANS = NONSEQ;
        HSIZE  = size;
        HWRITE = 1'b1;
        while (HREADY !== 1'b1) @(negedge HCLK);
 
        @(negedge HCLK);          // data phase
        HWDATA = write_data;
        HTRANS = IDLE;
        while (HREADY !== 1'b1) @(negedge HCLK);
        if (HRESP !== exp_resp || HREADY !== exp_ready) begin
            errors++;
            $display("FAIL @ %0t: %s", $time, msg);
            if (HRESP !== exp_resp)
                $display("  -> HRESP  expected %0b, got %0b", exp_resp, HRESP);
            if (HREADY !== exp_ready)
                $display("  -> HREADY expected %0b, got %0b", exp_ready, HREADY);
        end
    endtask
 
    // Two-cycle ERROR. A single-cycle helper structurally cannot express
    // this, which is why read_bus cannot be used for unmapped addresses.
    task automatic error_bus(input logic [31:0] addr, input string msg);
        @(negedge HCLK);
        HADDR  = addr;
        HTRANS = NONSEQ;
        HWRITE = 1'b0;
 
        @(negedge HCLK);          // ERROR cycle 1
        HTRANS = IDLE;            // the low HREADY gives us time to cancel
        if (HRESP !== 1'b1 || HREADY !== 1'b0)
            fail($sformatf("%s cycle 1: HRESP=%0b HREADY=%0b, want 1/0",
                           msg, HRESP, HREADY));
 
        @(negedge HCLK);          // ERROR cycle 2
        if (HRESP !== 1'b1 || HREADY !== 1'b1)
            fail($sformatf("%s cycle 2: HRESP=%0b HREADY=%0b, want 1/1",
                           msg, HRESP, HREADY));
    endtask
 
    //==================================================================
    // TRUE back-to-back reads to DIFFERENT subordinates.
    //
    // This is the only test that can detect an unregistered mux select.
    // Every other test holds HADDR pointing at the subordinate being read
    // while sampling, so hsel_comb and hsel_dphase agree and both a
    // correct and a broken interconnect pass.
    //
    // Here B's address phase overlaps A's data phase: hsel_comb points at
    // B while hsel_dphase points at A. A combinational select returns B's
    // data on the first check.
    //
    // THE #1 IS REQUIRED HERE. We change HADDR (a combinational input) and
    // sample HRDATA (a combinational output) in the same timestep, so
    // without elapsed time the order of the DUT's always_comb versus this
    // task is undefined. Everywhere else we sample values produced by
    // registers at an earlier edge, so no race exists and no delay is
    // needed.
    //==================================================================
    task automatic back_to_back(input logic [31:0] addr_a,
                                input logic [31:0] exp_a,
                                input logic [31:0] addr_b,
                                input logic [31:0] exp_b,
                                input string       msg);
        @(negedge HCLK);
        HADDR  = addr_a;
        HTRANS = NONSEQ;
        HSIZE  = WORD;
        HWRITE = 1'b0;
        while (HREADY !== 1'b1) @(negedge HCLK);   // address phase may extend
 
        @(negedge HCLK);          // A's data phase, B's address phase
        HADDR  = addr_b;
        HTRANS = NONSEQ;
        #1;
        while (HREADY !== 1'b1) @(negedge HCLK);   // address phase may extend
        if (HRDATA !== exp_a)
            fail($sformatf("%s beat 1: expected %08h, got %08h -- mux select may be unregistered",
                           msg, exp_a, HRDATA));
 
        @(negedge HCLK);          // B's data phase
        HTRANS = IDLE;
        while (HREADY !== 1'b1) @(negedge HCLK);   // address phase may extend
        if (HRDATA !== exp_b)
            fail($sformatf("%s beat 2: expected %08h, got %08h", msg, exp_b, HRDATA));
    endtask
 
    //==================================================================
    // Stimulus
    //==================================================================
    initial begin
        HRESETn = 1'b0;
        HADDR   = '0;
        HTRANS  = IDLE;
        HWRITE  = 1'b0;
        HSIZE   = WORD;
        HWDATA  = '0;
 
        step();
        step();
 
        //-------- TEST 0: reset state and instance parameters -----------
        // Checked WHILE reset is asserted. HREADY must be 1 here: with
        // hsel_dphase all zeros the interconnect mux falls through to its
        // defaults, and a 0 there would prevent the first load, holding
        // HREADY low forever.
        $display("--- TEST 0: reset state and instance parameters ---");
        if (HREADY !== 1'b1) fail("HREADY not 1 during reset");
        if (HRESP  !== 1'b0) fail("HRESP not 0 during reset");
        check_params();
 
        HRESETn = 1'b1;
        setup_mem();
        step();
 
        //-------- TEST 1: word reads from each subordinate --------------
        $display("--- TEST 1: word reads ---");
        read_bus(32'h4000_0000, WORD, 32'hDEADBEEF, 1'b0, 1'b1, "read sub0 @0x000");
        read_bus(32'h4001_0020, WORD, 32'hAABBCCDD, 1'b0, 1'b1, "read sub1 @0x020");
        read_bus(32'h4002_0100, WORD, 32'h11223344, 1'b0, 1'b1, "read sub2 @0x100");
 
        //-------- TEST 2: back-to-back, different subordinates ----------
        $display("--- TEST 2: back-to-back different subordinates ---");
        back_to_back(32'h4000_0000, 32'hDEADBEEF,
                     32'h4002_0100, 32'h11223344, "sub0 then sub2");
        back_to_back(32'h4001_0020, 32'hAABBCCDD,
                     32'h4000_0000, 32'hDEADBEEF, "sub1 then sub0");
        back_to_back(32'h4002_0100, 32'h11223344,
                     32'h4001_0020, 32'hAABBCCDD, "sub2 then sub1");
 
        //-------- TEST 3: halfword writes -------------------------------
        // Expectations ACCUMULATE, so each write is checked for touching
        // only its own lanes.
        $display("--- TEST 3: halfword writes ---");
        write_bus(32'h4001_00F0, HALF, 32'h1234BECE, 1'b0, 1'b1, "halfword write @0x0F0");
        read_bus (32'h4001_00F0, WORD, 32'h0000BECE, 1'b0, 1'b1, "verify low half");
        write_bus(32'h4001_00F2, HALF, 32'h9999EEEE, 1'b0, 1'b1, "halfword write @0x0F2");
        read_bus (32'h4001_00F0, WORD, 32'h9999BECE, 1'b0, 1'b1, "verify high half, low intact");
 
        //-------- TEST 4: byte writes, all four lanes -------------------
        $display("--- TEST 4: byte writes ---");
        write_bus(32'h4001_0FF0, BYTE, 32'hABCDEF27, 1'b0, 1'b1, "byte write lane 0");
        read_bus (32'h4001_0FF0, WORD, 32'h00000027, 1'b0, 1'b1, "verify lane 0");
        write_bus(32'h4001_0FF1, BYTE, 32'hAAAA17AA, 1'b0, 1'b1, "byte write lane 1");
        read_bus (32'h4001_0FF0, WORD, 32'h00001727, 1'b0, 1'b1, "verify lane 1");
        write_bus(32'h4001_0FF2, BYTE, 32'hABCD8888, 1'b0, 1'b1, "byte write lane 2");
        read_bus (32'h4001_0FF0, WORD, 32'h00CD1727, 1'b0, 1'b1, "verify lane 2");
        write_bus(32'h4001_0FF2, BYTE, 32'hCCAA8899, 1'b0, 1'b1, "byte rewrite lane 2");
        read_bus (32'h4001_0FF0, WORD, 32'h00AA1727, 1'b0, 1'b1, "verify lane 2 rewrite");
        write_bus(32'h4001_0FF3, BYTE, 32'h02FFFFFF, 1'b0, 1'b1, "byte write lane 3");
        read_bus (32'h4001_0FF0, WORD, 32'h02AA1727, 1'b0, 1'b1, "verify lane 3");
 
        //-------- TEST 5: reads are SIZE-INDEPENDENT --------------------
        // mem[0x0FF0..0x0FF3] now holds 27 17 AA 02, i.e. word 0x02AA1727.
        // All four addresses share one aligned word, and all three sizes
        // must return that SAME full word. A subordinate need only supply
        // valid data on the ACTIVE lanes, so returning the whole word is
        // conformant -- and lane placement comes from the ADDRESS, not
        // from HSIZE. If any of these returned a masked value, the read
        // path would be wrongly consulting size_reg.
        $display("--- TEST 5: read size independence ---");
        read_bus(32'h4001_0FF0, WORD, 32'h02AA1727, 1'b0, 1'b1, "word read @0xFF0");
        read_bus(32'h4001_0FF1, BYTE, 32'h02AA1727, 1'b0, 1'b1, "byte read @0xFF1, same word");
        read_bus(32'h4001_0FF2, HALF, 32'h02AA1727, 1'b0, 1'b1, "half read @0xFF2, same word");
        read_bus(32'h4001_0FF3, BYTE, 32'h02AA1727, 1'b0, 1'b1, "byte read @0xFF3, same word");
 
        //-------- TEST 6: unmapped address -> two-cycle ERROR -----------
        $display("--- TEST 6: unmapped ERROR ---");
        error_bus(32'h5000_0000, "unmapped 0x5000_0000");
        error_bus(32'h4000_1000, "gap above sub0");
        error_bus(32'h4001_2000, "gap above sub1");
 
        //-------- TEST 7: recovery after an error -----------------------
        $display("--- TEST 7: error recovery ---");
        read_bus(32'h4000_0000, WORD, 32'hDEADBEEF, 1'b0, 1'b1, "normal read after error");
        error_bus(32'h5000_0000, "second error after recovery");
        read_bus(32'h4001_0020, WORD, 32'hAABBCCDD, 1'b0, 1'b1, "normal read after 2nd error");
 
        //-------- TEST 8: region aliasing (per-instance ADDR_BITS) ------
        // Two addresses 4 KB apart inside sub 2's 16 KB region. If
        // ADDR_BITS were 12, both would map to offset 0 and the second
        // write would clobber the first.
        $display("--- TEST 8: region aliasing ---");
        write_bus(32'h4002_0000, WORD, 32'h11111111, 1'b0, 1'b1, "sub2 write @0x0000");
        write_bus(32'h4002_1000, WORD, 32'h22222222, 1'b0, 1'b1, "sub2 write @0x1000");
        write_bus(32'h4002_2000, WORD, 32'h33333333, 1'b0, 1'b1, "sub2 write @0x2000");
        write_bus(32'h4002_3000, WORD, 32'h44444444, 1'b0, 1'b1, "sub2 write @0x3000");
        read_bus (32'h4002_0000, WORD, 32'h11111111, 1'b0, 1'b1, "sub2 verify @0x0000");
        read_bus (32'h4002_1000, WORD, 32'h22222222, 1'b0, 1'b1, "sub2 verify @0x1000");
        read_bus (32'h4002_2000, WORD, 32'h33333333, 1'b0, 1'b1, "sub2 verify @0x2000");
        read_bus (32'h4002_3000, WORD, 32'h44444444, 1'b0, 1'b1, "sub2 verify @0x3000");
        // Same shape for sub 1's 8 KB region.
        write_bus(32'h4001_0000, WORD, 32'h55555555, 1'b0, 1'b1, "sub1 write @0x0000");
        write_bus(32'h4001_1000, WORD, 32'h66666666, 1'b0, 1'b1, "sub1 write @0x1000");
        read_bus (32'h4001_0000, WORD, 32'h55555555, 1'b0, 1'b1, "sub1 verify @0x0000");
        read_bus (32'h4001_1000, WORD, 32'h66666666, 1'b0, 1'b1, "sub1 verify @0x1000");
 
        //-------- TEST 9: cross-subordinate isolation -------------------
        $display("--- TEST 9: cross-subordinate isolation ---");
        write_bus(32'h4000_0004, WORD, 32'h08084050, 1'b0, 1'b1, "write sub0 @0x004");
        read_bus (32'h4000_0004, WORD, 32'h08084050, 1'b0, 1'b1, "verify sub0 @0x004");
        read_bus (32'h4000_0000, WORD, 32'hDEADBEEF, 1'b0, 1'b1, "sub0 @0x000 unchanged");
        read_bus (32'h4001_0020, WORD, 32'hAABBCCDD, 1'b0, 1'b1, "sub1 unchanged");
        read_bus (32'h4002_0100, WORD, 32'h11223344, 1'b0, 1'b1, "sub2 unchanged");
 
        //-------- TEST 10: HTRANS qualification -------------------------
        // IDLE and BUSY both have HTRANS[1] == 0, so neither may start a
        // data phase. We drive HWRITE high with poison on HWDATA and
        // confirm memory is untouched -- one bit rejects both encodings.
        $display("--- TEST 10: IDLE and BUSY must not transfer ---");
        write_bus(32'h4000_0008, WORD, 32'hB0B0B0B0, 1'b0, 1'b1, "seed @0x008");
 
        // IDLE with a write pending
        @(negedge HCLK);
        HADDR  = 32'h4000_0008;
        HTRANS = IDLE;
        HWRITE = 1'b1;
        HSIZE  = WORD;
        repeat (4) begin
            @(negedge HCLK);
            HWDATA = 32'hDEADDEAD;          // poison
            if (HREADY !== 1'b1) fail("HREADY dropped during IDLE");
            if (HRESP  !== 1'b0) fail("HRESP asserted during IDLE");
        end
 
        // BUSY with a write pending
        @(negedge HCLK);
        HTRANS = BUSY;
        repeat (4) begin
            @(negedge HCLK);
            HWDATA = 32'hBADBAD00;          // poison
            if (HREADY !== 1'b1) fail("HREADY dropped during BUSY");
            if (HRESP  !== 1'b0) fail("HRESP asserted during BUSY");
        end
 
        @(negedge HCLK);
        HTRANS = IDLE;
        HWRITE = 1'b0;
        read_bus(32'h4000_0008, WORD, 32'hB0B0B0B0, 1'b0, 1'b1,
                 "memory survived IDLE and BUSY");
 
        //-------- summary -----------------------------------------------
        step();
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $finish;
    end
 
    initial begin
        $dumpfile("AHB_TOP_TB.vcd");
        $dumpvars(0, AHB_TOP_TB);
    end
 
endmodule
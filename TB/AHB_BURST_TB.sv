//==============================================================================
// Author      : Brian Liau (brian.liau@tufts.edu)
// Module      : AHB_BURST_TB
// Description : Testbench for AHB_top interconnect module. Validates
//               BURST transfers for both INCR and WRAP burst types.
// Generated   : AHB_TB.vcd 
//==============================================================================
`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_BURST_TB;
    localparam logic [31:0] PAT0 = 32'hA000_0000;   // seed pattern per region
    localparam logic [31:0] PAT1 = 32'hB000_0000;
    localparam logic [31:0] PAT2 = 32'hC000_0000;
    localparam logic [31:0] WPAT = 32'hE000_0000;   // burst-write pattern

    // --- Testbench Signal Declarations ---
    logic        HCLK;         // System Clock
    logic        HRESETn;      // Active-Low Asynchronous Reset
    logic [31:0] HADDR;        // Address of Transfer
    logic [1:0]  HTRANS;       // Transfer Type (IDLE, BUSY, NONSEQ, SEQ)
    logic        HWRITE;       // Transfer Direction: 1 = Write, 0 = Read
    logic [2:0]  HSIZE;        // Transfer Size (BYTE, HALF, WORD)
    logic [31:0] HWDATA;       // Write Data Bus
    logic [31:0] HRDATA;       // Read Data Bus
    logic        HRESP;        // Transfer Response: 0 = OKAY, 1 = ERROR
    logic        HREADY;       // Transfer Done

    int errors = 0;            // Total test failure counter

    // Address sequence recorded by the burst helpers, so the WRAP order
    // can be asserted directly instead of inferred from the data.
    logic [31:0] seq_log [16];
    int          seq_len;

    // -- Device Under Testing (DUT) Instantiation ---  
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

    // --- Clock Generation (100 MHz) --- 
    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    // --- Watchdog Timer ---
    initial begin
        #200000;
        $display("ERROR: simulation timed out");
        $finish;
    end

    // ---------------------------------------------------------------------
    // Helper Tasks
    // ---------------------------------------------------------------------
    // --- Advance simulation to next negative clock edge ---
    task automatic step();
        @(negedge HCLK);
    endtask

    // --- Increase error count and show error message ---
    task automatic fail(input string msg);
        errors++;
        $display("FAIL @ %0t: %s", $time, msg);
    endtask

    // --- Calculates how many beats for each burst transfer in int form ---
    function automatic int beats_in(input logic [2:0] burst);
        case (burst)
            SINGLE       : return 1;
            WRAP4,  INCR4: return 4;
            WRAP8,  INCR8: return 8;
            WRAP16, INCR16:return 16;
            default      : return 0;    // INCR: undefined length, caller supplies
        endcase
    endfunction

    // --- Calculates how many beats for each burst transfer in array form ---
    function automatic logic [31:0] bytes_in(input logic [2:0] size);
        return 32'h1 << size;          // 1, 2, 4
    endfunction

    // --- Confirms if the transfer is a WRAP transfer type ---
    function automatic bit is_wrap(input logic [2:0] burst);
        return (burst == WRAP4) || (burst == WRAP8) || (burst == WRAP16);
    endfunction

    // WRAP: base is computed ONCE from the burst's start address
    // The & mask discards the carry out of the block; the | base
    // puts you back into the right block.
    function automatic logic [31:0] next_addr(input logic [31:0] a,
                                               input logic [31:0] start,
                                               input logic [2:0]  burst,
                                               input logic [2:0]  size,
                                               input int          nbeats);
        logic [31:0] bytes, total, mask, base;
        bytes = bytes_in(size);
        if (is_wrap(burst)) begin
            total = nbeats * bytes;
            mask  = total - 1;
            base  = start & ~mask;
            return base | ((a + bytes) & mask);
        end
        return a + bytes;
    endfunction

    // Only the INCR family can violate the 1 KB rule. WRAP cannot: its
    // maximum span on a 32-bit bus is 16 x 4 = 64 bytes, and the block is
    // 64-byte aligned by construction, so it always sits inside one 1 KB
    // block.
    function automatic bit crosses_1kb(input logic [31:0] start,
                                       input logic [2:0]  burst,
                                       input logic [2:0]  size,
                                       input int          nbeats);
        logic [31:0] last;
        if (is_wrap(burst)) return 1'b0;
        last = start + (nbeats * bytes_in(size)) - 1;
        return (start & ~32'h3FF) !== (last & ~32'h3FF);
    endfunction

    //==================================================================
    // Seed model: word at offset i of region r == PATr | i
    //==================================================================
    task automatic seed_mem();
        logic [31:0] w;
        for (int i = 0; i < 32'h1000; i += 4) begin
            w = PAT0 | i;
            dut.sub_gen[0].subordinate.mem[i+0] = w[7:0];
            dut.sub_gen[0].subordinate.mem[i+1] = w[15:8];
            dut.sub_gen[0].subordinate.mem[i+2] = w[23:16];
            dut.sub_gen[0].subordinate.mem[i+3] = w[31:24];
        end
        for (int i = 0; i < 32'h2000; i += 4) begin
            w = PAT1 | i;
            dut.sub_gen[1].subordinate.mem[i+0] = w[7:0];
            dut.sub_gen[1].subordinate.mem[i+1] = w[15:8];
            dut.sub_gen[1].subordinate.mem[i+2] = w[23:16];
            dut.sub_gen[1].subordinate.mem[i+3] = w[31:24];
        end
        for (int i = 0; i < 32'h4000; i += 4) begin
            w = PAT2 | i;
            dut.sub_gen[2].subordinate.mem[i+0] = w[7:0];
            dut.sub_gen[2].subordinate.mem[i+1] = w[15:8];
            dut.sub_gen[2].subordinate.mem[i+2] = w[23:16];
            dut.sub_gen[2].subordinate.mem[i+3] = w[31:24];
        end
    endtask

    // Expected HRDATA for any address: the full ALIGNED word. Reads are
    // size-independent, so this does not consult HSIZE.
    function automatic logic [31:0] exp_word(input logic [31:0] a);
        logic [31:0] off;
        if (a >= BASE_ADDR[0] && a < BASE_ADDR[0] + ADDR_SIZE[0]) begin
            off = a - BASE_ADDR[0]; return PAT0 | (off & ~32'h3);
        end
        if (a >= BASE_ADDR[1] && a < BASE_ADDR[1] + ADDR_SIZE[1]) begin
            off = a - BASE_ADDR[1]; return PAT1 | (off & ~32'h3);
        end
        if (a >= BASE_ADDR[2] && a < BASE_ADDR[2] + ADDR_SIZE[2]) begin
            off = a - BASE_ADDR[2]; return PAT2 | (off & ~32'h3);
        end
        return 32'h0;
    endfunction

    function automatic logic [31:0] wr_data(input logic [31:0] a);
        return WPAT | (a & 32'h0000_FFFF);
    endfunction

    //==================================================================
    // Bus helpers
    //==================================================================
    // Single word read, used to verify burst writes beat by beat.
    task automatic read_word(input logic [31:0] a,
                             input logic [31:0] exp,
                             input string       msg);
        step();
        HADDR = a; HTRANS = NONSEQ; HSIZE = WORD; HWRITE = 1'b0;
        while (HREADY !== 1'b1) step();
        step();
        HTRANS = IDLE;
        while (HREADY !== 1'b1) step();
        if (HRDATA !== exp)
            fail($sformatf("%s: HRDATA %08h, expected %08h", msg, HRDATA, exp));
    endtask

    // Beats are PIPELINED: beat b+1's address phase overlaps beat b's
    // data phase, so a new address goes out every cycle, not every other
    // cycle. The single while loop covers both overlapping phases, since
    // HREADY gates the whole pipeline at once.
    task automatic burst_read(input logic [31:0] start,
                              input logic [2:0]  burst,
                              input logic [2:0]  size,
                              input int          incr_beats,
                              input string       msg);
        int          nbeats;
        logic [31:0] a, exp;

        nbeats  = (burst == INCR) ? incr_beats : beats_in(burst);
        seq_len = 0;

        if (crosses_1kb(start, burst, size, nbeats))
            fail($sformatf("%s: burst crosses a 1 KB boundary", msg));

        a = start;
        step();
        HADDR = a; HTRANS = NONSEQ; HSIZE = size; HWRITE = 1'b0;
        while (HREADY !== 1'b1) step();

        for (int b = 0; b < nbeats; b++) begin
            seq_log[seq_len++] = a;
            exp = exp_word(a);          // capture BEFORE advancing a

            step();                     // beat b data phase / beat b+1 address phase
            if (b + 1 < nbeats) begin
                a      = next_addr(a, start, burst, size, nbeats);
                HADDR  = a;
                HTRANS = SEQ;
            end else begin
                HTRANS = IDLE;
            end
            while (HREADY !== 1'b1) step();

            if (HRDATA !== exp)
                fail($sformatf("%s beat %0d @%08h: HRDATA %08h, expected %08h",
                               msg, b, seq_log[b], HRDATA, exp));
        end
    endtask

    task automatic burst_write(input logic [31:0] start,
                               input logic [2:0]  burst,
                               input logic [2:0]  size,
                               input int          incr_beats,
                               input string       msg);
        int          nbeats;
        logic [31:0] a, d;

        nbeats  = (burst == INCR) ? incr_beats : beats_in(burst);
        seq_len = 0;

        if (crosses_1kb(start, burst, size, nbeats))
            fail($sformatf("%s: burst crosses a 1 KB boundary", msg));

        a = start;
        step();
        HADDR = a; HTRANS = NONSEQ; HSIZE = size; HWRITE = 1'b1;
        while (HREADY !== 1'b1) step();

        for (int b = 0; b < nbeats; b++) begin
            seq_log[seq_len++] = a;
            d = wr_data(a);             // data for THIS beat, before advancing

            step();
            HWDATA = d;                 // data phase, one cycle behind its address
            if (b + 1 < nbeats) begin
                a      = next_addr(a, start, burst, size, nbeats);
                HADDR  = a;
                HTRANS = SEQ;
            end else begin
                HTRANS = IDLE;
            end
            while (HREADY !== 1'b1) step();
        end
    endtask

    task automatic chk_seq(input int idx, input logic [31:0] exp, input string msg);
        if (seq_log[idx] !== exp)
            fail($sformatf("%s beat %0d address %08h, expected %08h",
                           msg, idx, seq_log[idx], exp));
    endtask

    //==================================================================
    // Main Test Execution Block
    //==================================================================
    initial begin
        // --- System Reset Initialization ---
        HRESETn = 1'b0;
        HADDR   = BASE_ADDR[0];
        HTRANS  = IDLE;
        HWRITE  = 1'b0;
        HSIZE   = WORD;
        HWDATA  = '0;

        step(); step();
        HRESETn = 1'b1;
        seed_mem();
        step();

        // --- TEST 1: address arithmetic, no bus traffic ---
        // Pure function checks. If these fail, nothing below is readable.
        $display("--- TEST 1: next_addr arithmetic ---");
        if (next_addr(32'h100, 32'h100, INCR4, WORD, 4) !== 32'h104)
            fail("INCR4 word: 0x100 -> 0x104");
        if (next_addr(32'h100, 32'h100, INCR4, HALF, 4) !== 32'h102)
            fail("INCR4 half: 0x100 -> 0x102");
        if (next_addr(32'h100, 32'h100, INCR4, BYTE, 4) !== 32'h101)
            fail("INCR4 byte: 0x100 -> 0x101");
        // WRAP4 words from 0x08: mask 0x0F, base 0x00 -> 08 0C 00 04
        if (next_addr(32'h08, 32'h08, WRAP4, WORD, 4) !== 32'h0C)
            fail("WRAP4: 0x08 -> 0x0C");
        if (next_addr(32'h0C, 32'h08, WRAP4, WORD, 4) !== 32'h00)
            fail("WRAP4 wrap point: 0x0C -> 0x00");
        if (next_addr(32'h00, 32'h08, WRAP4, WORD, 4) !== 32'h04)
            fail("WRAP4: 0x00 -> 0x04");
        // WRAP4 words from 0x1FF8: base 0x1FF0
        if (next_addr(32'h1FFC, 32'h1FF8, WRAP4, WORD, 4) !== 32'h1FF0)
            fail("WRAP4 wrap at 0x1FFC -> 0x1FF0");
        // WRAP8 words from 0x24: mask 0x1F, base 0x20
        if (next_addr(32'h3C, 32'h24, WRAP8, WORD, 8) !== 32'h20)
            fail("WRAP8 wrap at 0x3C -> 0x20");

        // --- TEST 2: the 1 KB rule ---
        // Includes a deliberate violator, so the check itself is tested.
        $display("--- TEST 2: 1 KB boundary detection ---");
        if (crosses_1kb(32'h4000_0000, INCR16, WORD, 16) !== 1'b0)
            fail("INCR16 at 0x000 should be legal");
        if (crosses_1kb(32'h4000_03D0, INCR16, WORD, 16) !== 1'b1)
            fail("INCR16 at 0x3D0 crosses 0x400 and should be flagged");
        if (crosses_1kb(32'h4000_03F8, WRAP4, WORD, 4) !== 1'b0)
            fail("WRAP can never cross a 1 KB boundary");

        // --- TEST 3: INCR4 read, zero wait states ---
        $display("--- TEST 3: INCR4 read, sub0 (0 waits) ---");
        burst_read(32'h4000_0100, INCR4, WORD, 0, "INCR4 sub0");
        chk_seq(0, 32'h4000_0100, "INCR4 sub0");
        chk_seq(1, 32'h4000_0104, "INCR4 sub0");
        chk_seq(2, 32'h4000_0108, "INCR4 sub0");
        chk_seq(3, 32'h4000_010C, "INCR4 sub0");

        // --- TEST 4: INCR4 read into a slow subordinate ---
        // sub2 has 3 wait states, so every beat stalls and beat N+1's
        // address phase extends alongside beat N's data phase. This is
        // the interaction that nothing before this file exercised.
        $display("--- TEST 4: INCR4 read, sub2 (3 waits) ---");
        burst_read(32'h4002_0200, INCR4, WORD, 0, "INCR4 sub2 slow");

        $display("--- TEST 5: INCR8 read, sub2 (3 waits) ---");
        burst_read(32'h4002_0300, INCR8, WORD, 0, "INCR8 sub2 slow");

        // --- TEST 6: WRAP4 from mid-block ---
        // The address sequence is the point, so assert it directly.
        $display("--- TEST 6: WRAP4 read from mid-block, sub1 (1 wait) ---");
        burst_read(32'h4001_0108, WRAP4, WORD, 0, "WRAP4 sub1");
        chk_seq(0, 32'h4001_0108, "WRAP4 sub1");
        chk_seq(1, 32'h4001_010C, "WRAP4 sub1");
        chk_seq(2, 32'h4001_0100, "WRAP4 sub1");   // wraps to block start
        chk_seq(3, 32'h4001_0104, "WRAP4 sub1");

        $display("--- TEST 7: WRAP8 read from mid-block, sub2 ---");
        burst_read(32'h4002_0424, WRAP8, WORD, 0, "WRAP8 sub2");
        chk_seq(0, 32'h4002_0424, "WRAP8 sub2");
        chk_seq(6, 32'h4002_043C, "WRAP8 sub2");
        chk_seq(7, 32'h4002_0420, "WRAP8 sub2");

        // --- TEST 8: sub-word burst ---
        // Byte beats crossing a word boundary. Confirms word_base and
        // byte_en are recomputed per beat.
        $display("--- TEST 8: INCR4 byte read crossing a word boundary ---");
        burst_read(32'h4001_0202, INCR4, BYTE, 0, "INCR4 byte sub1");
        chk_seq(0, 32'h4001_0202, "INCR4 byte");
        chk_seq(2, 32'h4001_0204, "INCR4 byte");   // now in the next word

        // --- TEST 9: INCR4 write then read back ---
        $display("--- TEST 9: INCR4 write, sub1 ---");
        burst_write(32'h4001_0500, INCR4, WORD, 0, "INCR4 write sub1");
        for (int b = 0; b < 4; b++)
            read_word(32'h4001_0500 + b*4, wr_data(32'h4001_0500 + b*4),
                      $sformatf("INCR4 write verify beat %0d", b));

        // --- TEST 10: WRAP4 write then read back ---
        // Verified in ASCENDING address order, not burst order: all four
        // words of the block must be written regardless of visit order.
        $display("--- TEST 10: WRAP4 write from mid-block, sub2 ---");
        burst_write(32'h4002_0608, WRAP4, WORD, 0, "WRAP4 write sub2");
        for (int b = 0; b < 4; b++)
            read_word(32'h4002_0600 + b*4, wr_data(32'h4002_0600 + b*4),
                      $sformatf("WRAP4 write verify word %0d", b));

        // --- TEST 11: undefined-length INCR ---
        $display("--- TEST 11: INCR with explicit length 6 ---");
        burst_read(32'h4000_0300, INCR, WORD, 6, "INCR6 sub0");
        chk_seq(5, 32'h4000_0314, "INCR6 sub0");

        // --- TEST 12: BUSY between beats ---
        // BUSY holds the NEXT beat's address while telling subordinates
        // not to start a data phase. Legal only inside a burst.
        $display("--- TEST 12: BUSY inserted mid-burst ---");
        begin
            logic [31:0] a;
            a = 32'h4000_0400;
            step();
            HADDR = a; HTRANS = NONSEQ; HSIZE = WORD; HWRITE = 1'b0;
            while (HREADY !== 1'b1) step();

            step();                             // beat 0 data phase
            a = a + 4; HADDR = a; HTRANS = SEQ;
            while (HREADY !== 1'b1) step();
            if (HRDATA !== exp_word(32'h4000_0400)) fail("BUSY test beat 0");

            step();                             // beat 1 data phase
            HTRANS = BUSY;                      // hold beat 2's address
            while (HREADY !== 1'b1) step();
            if (HRDATA !== exp_word(32'h4000_0404)) fail("BUSY test beat 1");

            step();                             // BUSY cycle: no data phase
            if (HREADY !== 1'b1) fail("BUSY must not stall the bus");
            a = a + 4; HADDR = a; HTRANS = SEQ;

            step();                             // beat 2 data phase
            HTRANS = IDLE;
            while (HREADY !== 1'b1) step();
            if (HRDATA !== exp_word(32'h4000_0408)) fail("BUSY test beat 2");
        end

        //--- Simulation Summary --- 
        step();
        if (errors == 0) $display("=== ALL BURST TESTS PASSED ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $finish;
    end

    // --- Waveform Dump ---
    initial begin
        $dumpfile("AHB_BURST_TB.vcd");
        $dumpvars(0, AHB_BURST_TB);
    end

endmodule
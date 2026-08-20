`timescale 1ns/1ps
//======================================================================
// I5c: AHB_interconnect testbench, widened for the default slot.
//
// TESTS 0-3  decoder    (combinational, HADDR -> HSELx)
// TESTS A-G  pipeline   (registered select, mux, freeze, ERROR routing)
//
// TIMING DISCIPLINE -- negedge only, no #delays anywhere.
//   At each negedge we first CHECK (state reflects the address driven one
//   cycle earlier) then DRIVE (for the coming posedge).
//
// THE DEFAULT SLOT CHANGES ONE THING FUNDAMENTALLY
//   Before I5b, an unmapped address gave hsel_comb == 0 and the mux fell
//   through to its defaults. Now bit 3 is set instead, so there is no
//   longer ANY address that produces hsel_dphase == 0 -- except the single
//   cycle between reset and the first accepted transfer.
//
//   "Idle" was never a decoder state. Idle is expressed by HTRANS, and
//   this module has no HTRANS port. Only subordinates can know the bus is
//   idle. So here we model idle by parking on the default slot and driving
//   its inputs the way an idle default subordinate would.
//
//   HRDATA_S[3] carries a DISTINCT payload (D3), not '0. That is what
//   separates "the mux routed slot 3" from "the mux fell through to its
//   default of zero" -- two behaviours that look identical if slot 3 also
//   drives zero.
//
// TEST 1 expectations assume ADDR_SIZE[2] = 32'h0000_4000. If TEST 0
// fails, fix AHB_pkg before reading any later result.
//======================================================================
module AHB_IC_TB;

    localparam int NSUB        = AHB_pkg::NUM_SUBORDINATES;   // 3 mapped
    localparam int NTOTAL      = NSUB + 1;                    // + default
    localparam int DEFAULT_IDX = NSUB;

    localparam logic [31:0] A0 = 32'h4000_0000;
    localparam logic [31:0] A1 = 32'h4001_0000;
    localparam logic [31:0] A2 = 32'h4002_0000;
    localparam logic [31:0] AX = 32'h5000_0000;   // unmapped -> default slot

    localparam logic [31:0] D0 = 32'hAAAA_0000;
    localparam logic [31:0] D1 = 32'hBBBB_1111;
    localparam logic [31:0] D2 = 32'hCCCC_2222;
    localparam logic [31:0] D3 = 32'hDDDD_3333;   // default slot payload

    logic              HCLK;
    logic              HRESETn;
    logic [31:0]       HADDR;
    logic [31:0]       HRDATA_S [NTOTAL];
    logic [NTOTAL-1:0] HREADYOUT_S;
    logic [NTOTAL-1:0] HRESP_S;
    logic [31:0]       HRDATA;
    logic              HREADY;
    logic              HRESP;
    logic [NTOTAL-1:0] HSELx;

    int errors = 0;

    AHB_interconnect dut (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .HADDR       (HADDR),
        .HRDATA_S    (HRDATA_S),
        .HREADYOUT_S (HREADYOUT_S),
        .HRESP_S     (HRESP_S),
        .HRDATA      (HRDATA),
        .HREADY      (HREADY),
        .HRESP       (HRESP),
        .HSELx       (HSELx)
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

    //==================================================================
    // Reference model -- INDEPENDENT formulation.
    //   DUT: magnitude comparison, then a NOR assigned into hsel_comb.
    //   Here: tag equality, then a concatenation.
    // Writing it the same way as the DUT would make the sweep tautological.
    //
    // Note (a >> k) rather than a[31:k]: a part-select bound must be
    // constant, and k varies per subordinate.
    //==================================================================
    function automatic logic [NTOTAL-1:0] ref_sel(input logic [31:0] a);
        logic [NSUB-1:0] mapped;
        int unsigned     k;
        mapped = '0;
        for (int i = 0; i < NSUB; i++) begin
            k = $clog2(AHB_pkg::ADDR_SIZE[i]);
            if ((a >> k) == (AHB_pkg::BASE_ADDR[i] >> k)) mapped[i] = 1'b1;
        end
        ref_sel = {~(|mapped), mapped};      // default bit is the MSB
    endfunction

    //==================================================================
    // Helpers
    //==================================================================
    task automatic step();
        @(negedge HCLK);
    endtask

    task automatic chk_dphase(input logic [NTOTAL-1:0] exp, input string msg);
        if (dut.hsel_dphase !== exp) begin
            errors++;
            $display("FAIL @ %0t: %s  hsel_dphase expected %b, got %b",
                     $time, msg, exp, dut.hsel_dphase);
        end
    endtask

    task automatic chk_bus(input logic [31:0] exp_rdata,
                           input logic        exp_resp,
                           input logic        exp_ready,
                           input string       msg);
        if (HRDATA !== exp_rdata) begin
            errors++;
            $display("FAIL @ %0t: %s  HRDATA expected %08h, got %08h",
                     $time, msg, exp_rdata, HRDATA);
        end
        if (HRESP !== exp_resp) begin
            errors++;
            $display("FAIL @ %0t: %s  HRESP expected %b, got %b",
                     $time, msg, exp_resp, HRESP);
        end
        if (HREADY !== exp_ready) begin
            errors++;
            $display("FAIL @ %0t: %s  HREADY expected %b, got %b",
                     $time, msg, exp_ready, HREADY);
        end
    endtask

    // Decoder check against a hand-written value. Verbose: TEST 1 only.
    task automatic dec_expect(input logic [31:0]       a,
                              input logic [NTOTAL-1:0] exp,
                              input string             msg);
        HADDR = a;
        step();                       // settle, and let the pipeline advance
        if (HSELx !== exp) begin
            errors++;
            $display("FAIL: %-30s HADDR=%08h expected=%b got=%b",
                     msg, a, exp, HSELx);
        end else begin
            $display("PASS: %-30s HADDR=%08h HSELx=%b", msg, a, HSELx);
        end
    endtask

    // Decoder check against the reference model. Quiet: failures only.
    task automatic dec_ref(input logic [31:0] a);
        HADDR = a;
        step();
        if (HSELx !== ref_sel(a)) begin
            errors++;
            $display("FAIL: HADDR=%08h  DUT=%b  reference=%b",
                     a, HSELx, ref_sel(a));
        end
    endtask

    //==================================================================
    // Background invariants, active during every test.
    //
    // HSELx is now STRICTLY one-hot: bit 3 is set exactly when no mapped
    // bit is, so the all-zeros case no longer exists. $onehot0 -> $onehot.
    //
    // hsel_dphase does NOT earn that upgrade. It is loaded from hsel_comb,
    // so it is one-hot once loaded -- but reset clears it, and it stays
    // zero until the first posedge with HREADY high. That single cycle is
    // why $onehot0 stays correct here and $onehot would false-fail once.
    //
    // `mirror` duplicates the select register, so it catches a wrong reset
    // value, wrong source, or wrong enable -- but not a misconception
    // shared by both copies. Its enable must match the DUT's: an
    // unconditional shadow would false-fail on every stall cycle in TEST F.
    //==================================================================
    logic [NTOTAL-1:0] mirror;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)    mirror <= '0;
        else if (HREADY) mirror <= dut.hsel_comb;
    end

    always @(negedge HCLK) begin
        if (HRESETn) begin
            if (dut.hsel_dphase !== mirror) begin
                errors++;
                $display("FAIL @ %0t: lag broken. hsel_dphase=%b mirror=%b",
                         $time, dut.hsel_dphase, mirror);
            end
            if (!$onehot0(dut.hsel_dphase)) begin
                errors++;
                $display("FAIL @ %0t: hsel_dphase not one-hot0: %b",
                         $time, dut.hsel_dphase);
            end
            if (!$onehot(HSELx)) begin
                errors++;
                $display("FAIL @ %0t: HSELx not one-hot: %b", $time, HSELx);
            end
        end
    end

    //==================================================================
    // Stimulus
    //==================================================================
    logic [31:0] base;
    logic [31:0] last;

    initial begin
        HRESETn     = 1'b0;
        HADDR       = AX;
        HRDATA_S[0] = D0;
        HRDATA_S[1] = D1;
        HRDATA_S[2] = D2;
        HRDATA_S[3] = D3;
        HREADYOUT_S = '1;      // all four ready, including the default slot
        HRESP_S     = '0;

        step();
        step();
        HRESETn = 1'b1;

        //---------------- TEST A: post-reset defaults -------------------
        // The ONLY cycle where hsel_dphase is all zeros, and therefore the
        // only cycle the mux defaults apply. HREADY must be 1: if it were
        // 0, hsel_dphase could never load, which would keep HREADY at 0
        // forever. The bus would never start.
        $display("--- TEST A: post-reset defaults ---");
        chk_dphase('0, "reset");
        chk_bus(32'h0, 1'b0, 1'b1, "reset");

        HRESETn = 1'b1;
        step();
        chk_dphase(4'b1000, "first load after reset -- bus started");

        //---------------- TEST 0: memory map sanity ---------------------
        $display("--- TEST 0: memory map sanity ---");
        for (int i = 0; i < NSUB; i++) begin
            if ((AHB_pkg::ADDR_SIZE[i] & (AHB_pkg::ADDR_SIZE[i] - 1)) != 0) begin
                errors++;
                $display("FAIL: ADDR_SIZE[%0d] = 0x%0h is not a power of two",
                         i, AHB_pkg::ADDR_SIZE[i]);
            end
            if ((AHB_pkg::BASE_ADDR[i] & (AHB_pkg::ADDR_SIZE[i] - 1)) != 0) begin
                errors++;
                $display("FAIL: BASE_ADDR[%0d] = 0x%0h is not aligned to its size",
                         i, AHB_pkg::BASE_ADDR[i]);
            end
        end

        //---------------- TEST 1: directed decode ----------------------
        // Every gap now expects 4'b1000, not zero.
        $display("--- TEST 1: directed decode ---");
        dec_expect(32'h3FFF_FFFF, 4'b1000, "just below sub 0");
        dec_expect(A0,            4'b0001, "sub 0 first byte");
        dec_expect(32'h4000_0800, 4'b0001, "sub 0 interior");
        dec_expect(32'h4000_0FFF, 4'b0001, "sub 0 last byte");
        dec_expect(32'h4000_1000, 4'b1000, "gap above sub 0");
        dec_expect(32'h4000_FFFF, 4'b1000, "just below sub 1");
        dec_expect(A1,            4'b0010, "sub 1 first byte");
        dec_expect(32'h4001_1000, 4'b0010, "sub 1 interior");
        dec_expect(32'h4001_1FFF, 4'b0010, "sub 1 last byte");
        dec_expect(32'h4001_2000, 4'b1000, "gap above sub 1");
        dec_expect(32'h4001_FFFF, 4'b1000, "just below sub 2");
        dec_expect(A2,            4'b0100, "sub 2 first byte");
        dec_expect(32'h4002_2000, 4'b0100, "sub 2 interior");
        dec_expect(32'h4002_3FFF, 4'b0100, "sub 2 last byte");
        dec_expect(32'h4002_4000, 4'b1000, "gap above sub 2");
        dec_expect(AX,            4'b1000, "outside all regions");
        dec_expect(32'h0000_0000, 4'b1000, "zero address");

        //---------------- TEST 2: derived boundaries --------------------
        $display("--- TEST 2: derived boundaries ---");
        for (int i = 0; i < NSUB; i++) begin
            base = AHB_pkg::BASE_ADDR[i];
            last = base + AHB_pkg::ADDR_SIZE[i] - 1;
            dec_ref(base - 1);    // catches >= vs >
            dec_ref(base);
            dec_ref(base + 1);
            dec_ref(last - 1);
            dec_ref(last);
            dec_ref(last + 1);    // catches <  vs <=
        end

        //---------------- TEST 3: strided sweep ------------------------
        $display("--- TEST 3: strided sweep vs reference model ---");
        for (int unsigned a = 32'h3FFF_0000; a <= 32'h4003_0000; a += 32'h100)
            dec_ref(a);

        //---------------- TEST B: one-cycle lag ------------------------
        $display("--- TEST B: one-cycle lag ---");
        HADDR = AX;
        step();                                               HADDR = A0;
        step(); chk_dphase(4'b0001, "lag sub0");              HADDR = A2;
        step(); chk_dphase(4'b0100, "lag sub2");              HADDR = A1;
        step(); chk_dphase(4'b0010, "lag sub1");              HADDR = AX;
        step(); chk_dphase(4'b1000, "lag default slot");      HADDR = A0;
        step(); chk_dphase(4'b0001, "lag back to sub0");      HADDR = AX;
        step(); chk_dphase(4'b1000, "lag default again");

        //---------------- TEST C: HRDATA routing -----------------------
        // Back-to-back different subordinates: what a combinational
        // (unregistered) select gets wrong. The final check proves slot 3
        // was ROUTED (D3) rather than the mux falling through (zero).
        $display("--- TEST C: HRDATA routing ---");
        step();                                               HADDR = A0;
        step(); chk_bus(D0, 1'b0, 1'b1, "route sub0");        HADDR = A2;
        step(); chk_bus(D2, 1'b0, 1'b1, "route sub2");        HADDR = A1;
        step(); chk_bus(D1, 1'b0, 1'b1, "route sub1");        HADDR = AX;
        step(); chk_bus(D3, 1'b0, 1'b1, "route default slot");

        //---------------- TEST D: HRESP routing ------------------------
        $display("--- TEST D: HRESP routing ---");
        HRESP_S[1] = 1'b1;                                   // sub 1 errors
        step();                                              HADDR = A1;
        step(); chk_bus(D1, 1'b1, 1'b1, "resp from sub1");   HADDR = A0;
        step(); chk_bus(D0, 1'b0, 1'b1, "sub0 unaffected");
        HRESP_S[1] = 1'b0;

        //---------------- TEST E: HREADYOUT routing --------------------
        // Only the SELECTED subordinate's ready reaches HREADY. Sub 2 must
        // own the data phase BEFORE sub 0 stalls -- otherwise sub 0's stall
        // freezes the select and the bus never reaches sub 2 (that is F).
        // An AND-reduce of HREADYOUT_S would fail here.
        $display("--- TEST E: HREADYOUT routing ---");
        HADDR = AX;
        step(); chk_dphase(4'b1000, "E: default before setup");
                HADDR          = A2;
                HREADYOUT_S[0] = 1'b0;      // sub 0 stalls, owns nothing
        step(); chk_dphase(4'b0100, "E: sub2 owns data phase");
                chk_bus(D2, 1'b0, 1'b1, "E: sub2 ready despite sub0 stall");
                HREADYOUT_S[0] = 1'b1;

        //---------------- TEST F: THE FREEZE --------------------------
        // Sub 0 stalls while the manager has already moved HADDR to sub 2.
        // The select must NOT advance -- if it did, the manager would see
        // sub 2's ready (high, sub 2 being idle), conclude its sub 0 read
        // had finished, and sample sub 2's data.
        $display("--- TEST F: select frozen while sub 0 stalls ---");
        HADDR = AX;
        step(); chk_dphase(4'b1000, "F: setup");
                HADDR          = A0;
                HREADYOUT_S[0] = 1'b0;

        step(); chk_dphase(4'b0001, "F: sub0 owns data phase");
                chk_bus(D0, 1'b0, 1'b0, "F: HREADY low");
                HADDR = A2;                 // manager moves on

        step(); chk_dphase(4'b0001, "F: stall 1 must not advance");
                chk_bus(D0, 1'b0, 1'b0, "F: still sub0 data");

        step(); chk_dphase(4'b0001, "F: stall 2 must not advance");
                chk_bus(D0, 1'b0, 1'b0, "F: still sub0 data");

        step(); chk_dphase(4'b0001, "F: stall 3 must not advance");
                chk_bus(D0, 1'b0, 1'b0, "F: still sub0 data");
                HREADYOUT_S[0] = 1'b1;      // sub 0 completes

        step(); chk_dphase(4'b0100, "F: advances to sub2 after release");
                chk_bus(D2, 1'b0, 1'b1, "F: sub2 data now");
                HADDR = AX;

        step(); chk_dphase(4'b1000, "F: back to default slot");

        //---------------- TEST G: two-cycle ERROR routing --------------
        // New for I5b. The interconnect never sees the real default
        // subordinate here -- slot 3 is just four inputs we drive by hand,
        // so we replay the two-cycle sequence manually and check the mux
        // carries BOTH cycles through. The two modules meet at I6.
        $display("--- TEST G: two-cycle ERROR through the mux ---");
        step(); chk_dphase(4'b1000, "G: default slot selected");
                chk_bus(D3, 1'b0, 1'b1, "G: idle default slot");
                HRESP_S[3]     = 1'b1;      // ERROR cycle 1
                HREADYOUT_S[3] = 1'b0;

        step(); chk_dphase(4'b1000, "G: still default slot");
                chk_bus(D3, 1'b1, 1'b0, "G: ERROR cycle 1 routed");
                HREADYOUT_S[3] = 1'b1;      // ERROR cycle 2

        step(); chk_dphase(4'b1000, "G: still default slot");
                chk_bus(D3, 1'b1, 1'b1, "G: ERROR cycle 2 routed");
                HRESP_S[3] = 1'b0;

        step(); chk_bus(D3, 1'b0, 1'b1, "G: recovered to OKAY");

        //---------------- summary --------------------------------------
        step();
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d FAILURE(S) ===", errors);
        $finish;
    end

    initial begin
        $dumpfile("AHB_IC_TB.vcd");
        $dumpvars(0, AHB_IC_TB);
    end

endmodule
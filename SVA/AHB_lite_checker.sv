//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_lite_checker.sv
// Design Unit : AHB_lite_checker
// Description : AHB Lite SystemVerilog Assertion that ensures proper signals 
//               from the AHB bus using Assertions and Coverage
// Dependencies: AHB_pkg.sv
// Target      : Verification
//------------------------------------------------------------------------------
interface AHB_lite_checker (
    // --- Clock and Reset ---
    input  logic        HCLK,           // System clock
    input  logic        HRESETn,        // Active low asynchronous reset

    // --- Address Phase Signals ---
    input logic [31:0]  HADDR,          // Address of Transaction
    input logic [1:0]   HTRANS,         // Transfer type: (00: IDLE, 01: BUSY, 10: NONSEQ, 11:SEQ)
    input logic         HWRITE,         // Transfer direction: (0: Read, 1: Write)
    input logic [2:0]   HSIZE,          // Transfer size: (000: Byte, 001: Halfword, 010: Word)

    // --- Data Phase Signals --- 
    input logic         HREADY,         // Bus wide ready signal
    input logic         HRESP,          // Bus wide response signal
    input logic [31:0]  HWDATA          // Transfer write data
);
    // --- Control and Address Stability ---
    property control_and_address_stability;
        @(posedge HCLK) disable iff (!HRESETn)
        ((!HREADY) && (HTRANS != AHB_pkg::IDLE)) |=> $stable(HADDR) && $stable(HTRANS) && $stable(HSIZE);
    endproperty
    assert_control_and_address_stability : assert property (control_and_address_stability)
        else $error ("Violation - control and address not stable");
    coverage_control_and_address_stability : cover property (
        @(posedge HCLK) disable iff (!HRESETn) 
        (!HREADY && (HTRANS != AHB_pkg::IDLE))  
    );

    // --- Write Data Stability ---
    property write_data_stability;
        @(posedge HCLK) disable iff (!HRESETn)
        ((HTRANS != AHB_pkg::IDLE) && (HWRITE)) ##1 (!HREADY) |=> $stable(HWDATA);
    endproperty
    assert_write_data_stability : assert property (write_data_stability)
        else $error ("Violation - Write data not stable");
    coverage_write_data_stability : cover property (
        @(posedge HCLK) disable iff (!HRESETn) 
        ((HTRANS != AHB_pkg::IDLE) && (HWRITE)) ##1 (!HREADY)
    );

    // --- Sequential Transfer ---
    property sequential_transfer;
        @(posedge HCLK) disable iff (!HRESETn)
        not ((HTRANS == AHB_pkg::IDLE) ##1 (HTRANS == AHB_pkg::SEQ));
    endproperty
    assert_sequential_transfer : assert property (sequential_transfer)
        else $error ("Violation - idle prior to sequential transfer");
    coverage_sequential_transfer : cover property (sequential_transfer);

    // --- Busy Transfer Stability ---
    property busy_transfer_stability;
        @(posedge HCLK) disable iff (!HRESETn)
        ((HTRANS == AHB_pkg::BUSY) && (!HREADY)) |=> ($stable(HADDR) && $stable(HTRANS) && $stable(HSIZE));
    endproperty
    assert_busy_transfer_stability : assert property (busy_transfer_stability)
        else $error ("Violation  control signals not stable during busy transfer");
    coverage_busy_transfer_stability : cover property (
        @(posedge HCLK) disable iff (!HRESETn)
        ((HTRANS == AHB_pkg::BUSY) && (!HREADY))
    );

    // --- Reset Set Idle ---
    property reset_sets_idle;
        @(posedge HCLK)
        !HRESETn |-> (HTRANS == AHB_pkg::IDLE);
    endproperty
    assert_reset_sets_idle : assert property (reset_sets_idle)
        else $error("Violation - Transfer not set to idle after reset");
    coverage_reset_sets_idle : cover property (
        @(posedge HCLK)
        !HRESETn
    );

    // --- HREADY After Reset ---
    property HREADY_after_reset;
        @(posedge HCLK)
        ($rose(HRESETn)) |-> (HREADY == 1'b1 && HRESP == 1'b0);
    endproperty
    assert_HREADY_after_reset : assert property (HREADY_after_reset)
        else $error("Violation - HREADY and HRESP are not set to ready after reset");
    coverage_HREADY_after_reset : cover property (
        @(posedge HCLK)
        $rose(HRESETn)
    );

    // --- Error Check First Cycle ---
    property error_check_first_cycle;
        @(posedge HCLK) disable iff (!HRESETn)
        ($rose(HRESP)) |-> (HREADY == 1'b0);
    endproperty
    assert_error_check_first_cycle : assert property (error_check_first_cycle)
        else $error("Violation - HREADY high during first cycle of error check");
    coverage_error_check_first_cycle : cover property (
        @(posedge HCLK) disable iff (!HRESETn)
        $rose(HRESP)
    );

    // --- Error Check Second Cycle ---
    property error_check_second_cycle;
        @(posedge HCLK) disable iff (!HRESETn)
        ((HRESP == 1'b1) && (HREADY == 1'b0)) |=> (HRESP == 1'b1 && HREADY == 1'b1);
    endproperty
    assert_error_check_second_cycle : assert property (error_check_second_cycle)
        else $error("Violation - Both HREADY and HRESP not set high on second cycle of error check");
    coverage_error_check_second_cycle : cover property (
        @(posedge HCLK) disable iff (!HRESETn)
        (HRESP == 1'b1) && (HREADY == 1'b0)
    );


    // --- Master Abort on Error ---
    property master_abort_on_error;
        @(posedge HCLK) disable iff (!HRESETn)
        ((HRESP == 1'b1) && (HREADY == 1'b1)) |=> (HTRANS == AHB_pkg::IDLE);
    endproperty
    assert_master_abort_on_error : assert property (master_abort_on_error)
        else $error("Violation - master did not issue IDLE after error");
    coverage_master_abort_on_error : cover property (
        @(posedge HCLK) disable iff (!HRESETn)
        (HRESP == 1'b1) && (HREADY == 1'b1)
    );

endinterface
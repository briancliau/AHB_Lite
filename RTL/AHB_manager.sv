//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_manager.sv
// Design Unit : AHB_manager
// Description : AHB Lite Manager Port Map
// Dependencies: AHB_pkg.sv
// Target      : Synthesis
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module AHB_manager (
    // --- Clock and Reset ---
    input  logic        HCLK,           // System clock
    input  logic        HRESETn,        // Active low asynchronous reset

    // --- Address Phase Signals ---
    output logic        HMASTLOCK,      // Master Lock Signal
    output logic [31:0] HADDR,          // Address of Transfer
    output logic [3:0]  HWSTRB,         // Transfer Write Strobe Signal
    output logic [2:0]  HSIZE,          // Transfer Size
    output logic [2:0]  HBURST,         // Transfer Burst Signal
    output logic [3:0]  HPROT,          // Transfer Protection Control Signal
    output logic [1:0]  HTRANS,         // Transfer type (00: IDLE, 01: BUSY, 10: NONSEQ, 11: SEQ)
    output logic        HWRITE,         // Transfer direction: (0: Read, 1: Write)

    // --- Data Phase Signals ---
    input  logic        HREADYOUT,      // Subordinate ready signal output to bus
    input  logic        HRESP,          // Subordinate response (0: Okay, 1: Error)
    input  logic [31:0] HRDATA,         // Read data bus
    output logic [31:0] HWDATA          // Write data bus    
);

endmodule

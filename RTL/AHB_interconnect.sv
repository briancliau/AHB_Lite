//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_interconnect.sv
// Design Unit : AHB_interconnect
// Description : AHB interconnect that sends proper signals between manager and subordinates
// Dependencies: AHB_pkg.sv
// Target      : Synthesizable
//------------------------------------------------------------------------------
`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_interconnect 
(
    // --- Clock and Reset ---
    input  logic        HCLK,           // System clock
    input  logic        HRESETn,        // Active low asynchronous reset

    // --- Address Phase Signals --- 
    input  logic [31:0]         HADDR,              // Address of transfer
    input  logic [31:0]         HRDATA_S [NTOTAL],  // Read Data from subordinates
    input  logic [NTOTAL-1:0]   HREADYOUT_S,        // Readyout signals from subordinates
    input  logic [NTOTAL-1:0]   HRESP_S,            // Response signals from subordinates
    output logic [NTOTAL-1:0]   HSELx,              // Selection signal to subordinates

    // --- Data Phase Signals
    output logic [31:0]         HRDATA,             // Read data to manager
    output logic                HREADY,             // Ready signal to manager
    output logic                HRESP               // Response signal to manager
);    
    // --- Internal Signals ---
    logic [NUM_SUBORDINATES-1:0]    hsel_subordinates;      // Array of Subordinates
    logic [NTOTAL-1:0]      hsel_comb;                      // Subordinate Selection Lines Combinational  
    logic [NTOTAL-1:0]      hsel_dphase;                    // Subordinate Selection Lines at Clock edge

    // Address phase combinational subordinate selection
    always_comb begin      
        for (int i = 0; i < NUM_SUBORDINATES; i++) begin
            hsel_subordinates[i] = HADDR >= BASE_ADDR[i] && HADDR < (BASE_ADDR[i] + ADDR_SIZE[i]);
        end

        hsel_comb = {~(|hsel_subordinates), hsel_subordinates};
        HSELx = hsel_comb;
    end

    // Address phase subordinate and clock alignment
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            hsel_dphase <= '0;
        end else if (HREADY) begin
            hsel_dphase <= hsel_comb;
        end
    end

    // Data phase response management
    always_comb begin
        HRDATA = '0;
        HRESP  = 1'b0;
        HREADY = 1'b1;

        for (int i = 0; i < NUM_SUBORDINATES + 1; i++) begin
            if (hsel_dphase[i]) begin
                HRDATA = HRDATA_S[i];
                HRESP = HRESP_S[i];
                HREADY = HREADYOUT_S[i];
            end
        end
    end
endmodule
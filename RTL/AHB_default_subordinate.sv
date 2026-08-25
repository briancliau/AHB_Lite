//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_default_subordinate.sv
// Design Unit : AHB_default_subordinate
// Description : Default AHB subordinate returning set responses back to top
// Dependencies: AHB_pkg.sv
// Target      : Synthesizable
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module AHB_default_subordinate (
    // --- Clock and Reset ---
    input  logic        HCLK,           // System clock
    input  logic        HRESETn,        // Active low asynchronous reset

    // --- Address Phase Signals ---
    input  logic        HSELx,          // Subordinate select signal
    input  logic        HREADY,         // Bus wide ready signal
    input  logic [1:0]  HTRANS,         // Transfer type (00: IDLE, 01: BUSY, 10: NONSEQ, 11: SEQ)

    // --- Data Phase Signals ---
    output logic        HREADYOUT,      // Subordinate ready signal output to bus
    output logic        HRESP,          // Subordinate response (0: Okay, 1: Error)
    output logic [31:0] HRDATA          // Read data bus (tied to 0)
);
    // --- Internal Signals ---
    logic addr_accept;              // High when valid transfer in address phase
    logic dataphase_valid;          // Tracks active data phase
    logic error_second;             // Tracks 2nd cycle of AHB error response

    // Combinational Assignments
    assign addr_accept = HSELx && HTRANS[1];
    assign HRDATA = '0;
    assign HRESP = dataphase_valid;
    assign HREADYOUT = ~(dataphase_valid && !error_second);

    // Tracks valid transfers requests when HREADY is high during address phase
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            dataphase_valid <= 1'b0;
        end else if (HREADY) begin
            dataphase_valid <= addr_accept;
        end
    end

    // Provides correct 2 cycle error response required of AHB protocol
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            error_second <= 1'b0;
        end else begin
            error_second <= dataphase_valid && !error_second;
        end
    end
endmodule

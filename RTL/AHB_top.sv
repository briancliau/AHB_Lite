//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_top.sv
// Design Unit : AHB_top
// Description : AHB interconnect and subordinate setup for manager connection
// Dependencies: AHB_pkg.sv
// Target      : Synthesizable
//------------------------------------------------------------------------------
`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_top (
    // --- Clock and Reset ---
    input  logic        HCLK,           // System clock
    input  logic        HRESETn,        // Active low asynchronous reset

    // --- Address Phase Signals ---
    input  logic [31:0] HADDR,          // Address of Transfer     
    input  logic [1:0]  HTRANS,         // Transfer type (00: IDLE, 01: BUSY, 10: NONSEQ, 11: SEQ)
    input  logic        HWRITE,         // Transfer direction: (0: Read, 1: Write)
    input  logic [2:0]  HSIZE,          // Transfer size

    // -- Data Phase Signals --- 
    input  logic [31:0] HWDATA,         // Write data bus
    output logic [31:0] HRDATA,         // Read data bus
    output logic        HRESP,          // Subordinate response (0: Okay, 1: Error) 
    output logic        HREADY          // AHB bus ready signal
);
    // --- Interconnect output signals --- 
    logic [NTOTAL-1:0]  HSELx;

    // --- Subordinate output signals to interconnect ---
    logic [NTOTAL-1:0]  HREADYOUT_S;
    logic [NTOTAL-1:0]  HRESP_S;
    logic [31:0]        HRDATA_S [NTOTAL];

    // --- Interconnect Instantiation ---
    AHB_interconnect ic (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR(HADDR),
        .HRDATA_S(HRDATA_S),
        .HREADYOUT_S(HREADYOUT_S),
        .HRESP_S(HRESP_S),
        .HRDATA(HRDATA),
        .HREADY(HREADY),
        .HRESP(HRESP),
        .HSELx(HSELx)
    );

    // --- Subordinate Instantiation ---
    generate
        for (genvar i = 0; i < NUM_SUBORDINATES; i++) begin : sub_gen
            if ((32'h1 << ADDR_BITS[i]) != ADDR_SIZE[i])
                $error("ADDR_SIZE[%0d] = 0x%0h is not a power of two", i, ADDR_SIZE[i]);
            if ((BASE_ADDR[i] & (ADDR_SIZE[i] - 1)) != 32'h0)
                $error("BASE_ADDR[%0d] = 0x%0h is not naturally aligned", i, BASE_ADDR[i]);
            
            AHB_subordinate #(.ADDR_BITS(ADDR_BITS[i]), .NUM_WAITS(WAIT_STATES[i])) subordinate
            (
                .HCLK      (HCLK),
                .HRESETn   (HRESETn),
                .HSELx     (HSELx[i]),
                .HREADY    (HREADY),
                .HWRITE    (HWRITE),
                .HADDR     (HADDR),
                .HSIZE     (HSIZE),
                .HTRANS    (HTRANS),
                .HWDATA    (HWDATA),
                .HRESP     (HRESP_S[i]),
                .HREADYOUT (HREADYOUT_S[i]),
                .HRDATA    (HRDATA_S[i])
            );
        end
    endgenerate

    // --- Default Subordinate Instantiation ---
    AHB_default_subordinate default_subordinate (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSELx(HSELx[DEFAULT_IDX]),
        .HREADY(HREADY),
        .HTRANS(HTRANS),
        .HREADYOUT(HREADYOUT_S[DEFAULT_IDX]),
        .HRESP(HRESP_S[DEFAULT_IDX]),
        .HRDATA(HRDATA_S[DEFAULT_IDX])
    );

endmodule

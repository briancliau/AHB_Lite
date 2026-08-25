//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_pkg.sv
// Design Unit : AHB_pkg
// Description : AHB Lite definitions
// Target      : Synthesis
//------------------------------------------------------------------------------
`timescale 1ns/1ps
`ifndef AHB_PKG_SV
`define AHB_PKG_SV

package AHB_pkg;
    
    // --- Subordinate Information --- 
    parameter int NUM_SUBORDINATES = 3;
    localparam int NTOTAL      = NUM_SUBORDINATES + 1;
    localparam int DEFAULT_IDX = NUM_SUBORDINATES;
    localparam int unsigned WAIT_STATES[NUM_SUBORDINATES] = '{0, 1, 3};

    // Use curly braces to define unique values for each index
    parameter logic [31:0] BASE_ADDR [NUM_SUBORDINATES] = '{
        32'h4000_0000, 
        32'h4001_0000, 
        32'h4002_0000
    };

    parameter logic [31:0] ADDR_SIZE [NUM_SUBORDINATES] = '{
        32'h0000_1000, 
        32'h0000_2000, 
        32'h0000_4000
    };

    parameter int ADDR_BITS [NUM_SUBORDINATES] = '{
        $clog2(ADDR_SIZE[0]),
        $clog2(ADDR_SIZE[1]),
        $clog2(ADDR_SIZE[2])
    };

    // --- Transfer Size --- 
    localparam logic [2:0] BYTE = 3'b000;
    localparam logic [2:0] HALF = 3'b001;
    localparam logic [2:0] WORD = 3'b010;

    // --- Transfer Types ---
    localparam logic [1:0] IDLE     = 2'b00;
    localparam logic [1:0] BUSY     = 2'b01;
    localparam logic [1:0] NONSEQ   = 2'b10;
    localparam logic [1:0] SEQ      = 2'b11;

    // --- Burst Types --- 
    localparam logic [2:0] SINGLE = 3'b000;
    localparam logic [2:0] INCR   = 3'b001;
    localparam logic [2:0] WRAP4  = 3'b010;
    localparam logic [2:0] INCR4  = 3'b011;
    localparam logic [2:0] WRAP8  = 3'b100;
    localparam logic [2:0] INCR8  = 3'b101;
    localparam logic [2:0] WRAP16 = 3'b110;
    localparam logic [2:0] INCR16 = 3'b111;

endpackage

`endif
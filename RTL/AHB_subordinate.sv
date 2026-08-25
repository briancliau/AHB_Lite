//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_subordinate.sv
// Design Unit : AHB_subordinate
// Description : AHB subordinate Structure, currently memory module
// Dependencies: AHB_pkg.sv
// Target      : Synthesizable
//------------------------------------------------------------------------------
`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_subordinate 
#(parameter int unsigned ADDR_BITS, parameter int unsigned NUM_WAITS = 0)
(
   // --- Clock and Reset ---
    input  logic        HCLK,           // System clock
    input  logic        HRESETn,        // Active low asynchronous reset

    // --- Address Phase Signals ---
    input  logic        HSELx,          // Subordinate select signal
    input  logic        HREADY,         // Bus wide ready signal
    input  logic [31:0] HADDR,          // Address of Transfer     
    input  logic [1:0]  HTRANS,         // Transfer type (00: IDLE, 01: BUSY, 10: NONSEQ, 11: SEQ)
    input  logic        HWRITE,         // Transfer direction: (0: Read, 1: Write)
    input  logic [2:0]  HSIZE,          // Transfer size
    
    // -- Data Phase Signals --- 
    input  logic [31:0] HWDATA,         // Write data bus
    output logic        HRESP,          // Subordinate response (0: Okay, 1: Error)
    output logic        HREADYOUT,      // Subordinate ready signal output to bus
    output logic [31:0] HRDATA          // Read data bus
);    
   
    // --- Internal Signals ---
    // Phase Logic
    logic                   addr_accept;
    logic                   dataphase_valid;
    // Registers storing address phase information
    logic                   write_reg;
    logic [ADDR_BITS-1:0]   addr_reg;
    logic [2:0]             size_reg;
    // Data phase logic
    logic [ADDR_BITS-1:0]   word_base;
    // Memory and Byte Enable
    logic [7:0] mem [2**ADDR_BITS];
    logic [3:0] byte_en;
    // Wait counter
    localparam int unsigned counter_width = (NUM_WAITS > 0) ? $clog2(NUM_WAITS + 1) : 1;
    logic [counter_width-1:0] wait_count;

    // --- Combinational Logic Assignment ---
    assign addr_accept = HSELx && HTRANS[1];
    assign word_base = {addr_reg[ADDR_BITS-1:2], 2'b00};

    // --- Byte Enable Signal Assignment ---
    always_comb begin
        case (size_reg) 
            BYTE:     byte_en = 4'b0001 << addr_reg[1:0];
            HALF:     byte_en = addr_reg[1] ? 4'b1100 : 4'b0011;
            WORD:     byte_en = 4'b1111;
            default:  byte_en = 4'b0000;
        endcase
    end

    // --- Phase Logic Updates ---
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            dataphase_valid <= 1'b0;
            write_reg       <= 1'b0;              // LOW = read so preserves memory
            addr_reg        <= '0;             // Set to default address
            size_reg        <= 3'b000;             // Set to 0

        end else if (HREADY) begin
            dataphase_valid <= addr_accept;

            if (addr_accept) begin
                write_reg   <= HWRITE;
                addr_reg    <= HADDR[ADDR_BITS-1:0]; 
                size_reg    <= HSIZE;
            end
        end
    end

    // --- Write Data Logic ---
    always_ff @(posedge HCLK) begin
        if (dataphase_valid && HREADYOUT && write_reg) begin
            if (byte_en[3]) mem[word_base + 3] <= HWDATA[31:24];
            if (byte_en[2]) mem[word_base + 2] <= HWDATA[23:16];
            if (byte_en[1]) mem[word_base + 1] <= HWDATA[15:8];
            if (byte_en[0]) mem[word_base    ] <= HWDATA[7:0];
        end
    end

    // --- Wait Count Logic --- 
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)                    wait_count <= '0;
        else if (HREADY && addr_accept)  wait_count <= NUM_WAITS[counter_width-1:0];    // load on accept
        else if (wait_count != '0)       wait_count <= wait_count - 1;    // count down
    end

    // --- Response, ReadyOut and Read Data Signal Assignments ---
    assign HRESP = 1'b0;
    assign HREADYOUT = (wait_count == '0);
    assign HRDATA    = {mem[word_base + 3], mem[word_base + 2], mem[word_base + 1], mem[word_base]};

endmodule

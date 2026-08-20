`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_subordinate 
#(parameter int unsigned ADDR_BITS, parameter int unsigned NUM_WAITS = 0)
(
    input  logic        HCLK, 
    input  logic        HRESETn,
    input  logic        HSELx,          
    input  logic        HREADY,
    input  logic        HWRITE,         // HIGH = WRITE, LOW = READ        
    input  logic [31:0] HADDR,          
    input  logic [2:0]  HSIZE,
    input  logic [1:0]  HTRANS,
    input  logic [31:0] HWDATA, 
    output logic        HRESP,
    output logic        HREADYOUT,
    output logic [31:0] HRDATA
);    
   
    // Phase Logic
    logic                   addr_accept;
    logic                   dataphase_valid;
    logic                   write_reg;
    logic [ADDR_BITS-1:0]   addr_reg;
    logic [2:0]             size_reg;
    assign addr_accept = HSELx && HTRANS[1];

    logic [ADDR_BITS-1:0]   word_base;
    assign word_base = {addr_reg[ADDR_BITS-1:2], 2'b00};

    logic [7:0] mem [2**ADDR_BITS];
    logic [3:0] byte_en;

    localparam int unsigned counter_width = (NUM_WAITS > 0) ? $clog2(NUM_WAITS + 1) : 1;
    logic [counter_width-1:0] wait_count;

    always_comb begin
        case (size_reg) 
            BYTE:     byte_en = 4'b0001 << addr_reg[1:0];
            HALF:     byte_en = addr_reg[1] ? 4'b1100 : 4'b0011;
            WORD:     byte_en = 4'b1111;
            default:  byte_en = 4'b0000;
        endcase
    end

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

    always_ff @(posedge HCLK) begin
        if (dataphase_valid && HREADYOUT && write_reg) begin
            if (byte_en[3]) mem[word_base + 3] <= HWDATA[31:24];
            if (byte_en[2]) mem[word_base + 2] <= HWDATA[23:16];
            if (byte_en[1]) mem[word_base + 1] <= HWDATA[15:8];
            if (byte_en[0]) mem[word_base    ] <= HWDATA[7:0];
        end
    end

     always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)                    wait_count <= '0;
        else if (HREADY && addr_accept)  wait_count <= NUM_WAITS[counter_width-1:0];    // load on accept
        else if (wait_count != '0)       wait_count <= wait_count - 1;    // count down
    end

    assign HRESP = 1'b0;
    assign HREADYOUT = (wait_count == '0);
    assign HRDATA    = {mem[word_base + 3], mem[word_base + 2], mem[word_base + 1], mem[word_base]};

endmodule

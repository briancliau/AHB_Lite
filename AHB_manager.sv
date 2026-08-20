`timescale 1ns/1ps

module AHB_manager (
    input logic         HCLK,
    input logic         HRESETn,
    input logic         HREADY,
    input logic         HRESP,
    input logic [31:0]  HRDATA,
    output logic        HWRITE,
    output logic        HMASTLOCK,
    output logic [31:0] HADDR,
    output logic [3:0]  HWSTRB,
    output logic [2:0]  HSIZE,
    output logic [2:0]  HBURST,
    output logic [3:0]  HPROT,
    output logic [1:0]  HTRANS,
    output logic [31:0] HWDATA
);

endmodule

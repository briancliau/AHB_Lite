`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_top (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic [31:0] HADDR,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [2:0]  HSIZE,
    input  logic [31:0] HWDATA,
    output logic [31:0] HRDATA,
    output logic        HRESP,
    output logic        HREADY
);
    // Interconnect output signals
    logic [NTOTAL-1:0]  HSELx;

    // Subordinate output arrays back to interconnect
    logic [NTOTAL-1:0]  HREADYOUT_S;
    logic [NTOTAL-1:0]  HRESP_S;
    logic [31:0]        HRDATA_S [NTOTAL];

    // Interconnect instantiation
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

    // Subordinate instantiations
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

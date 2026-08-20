`timescale 1ns/1ps
import AHB_pkg::*;

module AHB_interconnect 
(
    input  logic                HCLK,
    input  logic                HRESETn,
    input  logic [31:0]         HADDR,
    input  logic [31:0]         HRDATA_S [NTOTAL],
    input  logic [NTOTAL-1:0]   HREADYOUT_S,
    input  logic [NTOTAL-1:0]   HRESP_S,
    output logic [31:0]         HRDATA,
    output logic                HREADY,
    output logic                HRESP,
    output logic [NTOTAL-1:0]   HSELx
);    
    logic [NUM_SUBORDINATES-1:0]    hsel_subordinates;
    logic [NTOTAL-1:0]      hsel_comb;
    logic [NTOTAL-1:0]      hsel_dphase;
    assign HSELx = hsel_comb;

    // Address Phase
    always_comb begin      
        for (int i = 0; i < NUM_SUBORDINATES; i++) begin
            hsel_subordinates[i] = HADDR >= BASE_ADDR[i] && HADDR < (BASE_ADDR[i] + ADDR_SIZE[i]);
        end

        hsel_comb = {~(|hsel_subordinates), hsel_subordinates};
    end

    // Data Phase
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

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            hsel_dphase <= '0;
        end else if (HREADY) begin
            hsel_dphase <= hsel_comb;
        end
    end


endmodule
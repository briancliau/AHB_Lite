`timescale 1ns/1ps

module AHB_default_subordinate (
    input  logic        HCLK,
    input  logic        HRESETn,
    input  logic        HSELx,
    input  logic        HREADY,
    input  logic [1:0]  HTRANS,
    output logic        HREADYOUT,
    output logic        HRESP,
    output logic [31:0] HRDATA
);
    logic addr_accept;
    logic dataphase_valid;
    logic error_second;

    assign addr_accept = HSELx && HTRANS[1];
    assign HRDATA = '0;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            dataphase_valid <= 1'b0;
        end else if (HREADY) begin
            dataphase_valid <= addr_accept;
        end
    end

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            error_second <= 1'b0;
        end else begin
            error_second <= dataphase_valid && !error_second;
        end
    end

    assign HRESP = dataphase_valid;
    assign HREADYOUT = ~(dataphase_valid && !error_second);
endmodule

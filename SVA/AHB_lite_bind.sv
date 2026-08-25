//------------------------------------------------------------------------------
// Author      : Brian Liau (brian.liau@tufts.edu)
// File        : AHB_lite_bind.sv
// Design Unit : AHB_lite_bind
// Description : AHB Lite bind module for AHB_top and AHB_lite_checker
// Dependencies: AHB_pkg.sv
// Target      : Verification
//------------------------------------------------------------------------------
module AHB_lite_bind;
    bind AHB_top AHB_lite_checker u_ahb_checker (
        .HCLK   (HCLK),
        .HRESETn(HRESETn),
        .HADDR  (HADDR),
        .HTRANS (HTRANS),
        .HREADY (HREADY),
        .HRESP  (HRESP),
        .HWRITE (HWRITE),
        .HSIZE  (HSIZE),
        .HWDATA (HWDATA)
    );
endmodule
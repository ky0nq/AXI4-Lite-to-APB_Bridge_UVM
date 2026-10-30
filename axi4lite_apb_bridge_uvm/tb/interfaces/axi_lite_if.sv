`timescale 1ns/1ps
// ARESETn belongs to the AXI interface. It is the only reset source: tb_top
// connects it to the DUT and to apb_if (PRESETn), tests drive it through
// apply_reset(). It starts asserted and stays low until the first apply_reset.
interface axi_lite_if(input logic clk);
  logic resetn = 1'b0;
  logic [31:0] awaddr, wdata, araddr, rdata;
  logic [2:0] awprot, arprot;
  logic [3:0] wstrb;
  logic [1:0] bresp, rresp;
  logic awvalid, awready, wvalid, wready, bvalid, bready;
  logic arvalid, arready, rvalid, rready;

  // Pre-edge samples represent the values used by the DUT handshake.
  clocking mon_cb @(posedge clk);
    default input #1step;
    input resetn, awaddr, awprot, awvalid, awready;
    input wdata, wstrb, wvalid, wready, bresp, bvalid, bready;
    input araddr, arprot, arvalid, arready, rdata, rresp, rvalid, rready;
  endclocking

  // Changes on negedge so posedge samplers never race the reset edge.
  task automatic apply_reset(input int cycles = 5);
    @(negedge clk);
    resetn = 1'b0;
    repeat (cycles) @(negedge clk);
    resetn = 1'b1;
  endtask
endinterface

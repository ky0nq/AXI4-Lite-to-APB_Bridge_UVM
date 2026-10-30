`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import bridge_pkg::*;
  `include "uvm_macros.svh"

  bit clk = 0;
  always #5 clk = ~clk;
  axi_lite_if axi(clk);
  apb_if apb(clk, axi.resetn);

  APB_v1_0 #(
    .C_S00_AXI_DATA_WIDTH(32), .C_S00_AXI_ADDR_WIDTH(32), .APB_WIDTH(16)
  ) dut (
    .s00_axi_aclk(clk), .s00_axi_aresetn(axi.resetn),
    .s00_axi_awaddr(axi.awaddr), .s00_axi_awprot(axi.awprot),
    .s00_axi_awvalid(axi.awvalid), .s00_axi_awready(axi.awready),
    .s00_axi_wdata(axi.wdata), .s00_axi_wstrb(axi.wstrb),
    .s00_axi_wvalid(axi.wvalid), .s00_axi_wready(axi.wready),
    .s00_axi_bresp(axi.bresp), .s00_axi_bvalid(axi.bvalid),
    .s00_axi_bready(axi.bready),
    .s00_axi_araddr(axi.araddr), .s00_axi_arprot(axi.arprot),
    .s00_axi_arvalid(axi.arvalid), .s00_axi_arready(axi.arready),
    .s00_axi_rdata(axi.rdata), .s00_axi_rresp(axi.rresp),
    .s00_axi_rvalid(axi.rvalid), .s00_axi_rready(axi.rready),
    .PADDR(apb.paddr), .PSEL_UART(apb.psel[0]),
    .PSEL_GPIO(apb.psel[1]), .PSEL_TIMER(apb.psel[2]),
    .PENABLE(apb.penable), .PWRITE(apb.pwrite),
    .PWDATA(apb.pwdata), .PSTRB(apb.pstrb), .PPROT(apb.pprot),
    .PREADY_UART(apb.pready[0]), .PREADY_GPIO(apb.pready[1]),
    .PREADY_TIMER(apb.pready[2]),
    .PSLVERR_UART(apb.pslverr[0]), .PSLVERR_GPIO(apb.pslverr[1]),
    .PSLVERR_TIMER(apb.pslverr[2]),
    .PRDATA_UART(apb.prdata_uart), .PRDATA_GPIO(apb.prdata_gpio),
    .PRDATA_TIMER(apb.prdata_timer)
  );

  bridge_protocol_checker checker_i(axi, apb);

  initial begin
    bridge_cfg cfg;
    string test_name;
    cfg = bridge_cfg::type_id::create("cfg");
    cfg.axi_vif = axi;
    cfg.apb_vif = apb;
    cfg.strict_apb = 1;
    if ($value$plusargs("NUM_RANDOM=%d", cfg.num_random)) begin end
    if ($value$plusargs("TIMEOUT_CYCLES=%d", cfg.timeout_cycles)) begin end
    uvm_config_db#(bridge_cfg)::set(null, "uvm_test_top", "cfg", cfg);
    // Preserve command-line test selection, including standard UVM overrides.
    if ($value$plusargs("UVM_TESTNAME=%s", test_name)) run_test();
    else run_test("bridge_smoke_test");
  end

  initial begin
    #2ms;
    `uvm_fatal("WATCHDOG", "Global simulation timeout (2 ms)")
  end
endmodule

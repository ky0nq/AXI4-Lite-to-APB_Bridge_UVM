`timescale 1ns/1ps
`include "uvm_macros.svh"

// Procedural sampled checks avoid requiring concurrent SVA support. Both
// interfaces sample one timestep before the rising edge, as do all monitors.
module bridge_protocol_checker(axi_lite_if axi, apb_if apb);
  import uvm_pkg::*;

  bit strict_apb;
  string test_name;
  bit aw_stalled, w_stalled, ar_stalled, b_stalled, r_stalled;
  logic [34:0] last_aw, last_ar;
  logic [35:0] last_w;
  logic [1:0] last_b;
  logic [33:0] last_r;

  bit previous_setup, previous_wait, previous_completion;
  logic [56:0] last_apb;
  logic [56:0] current_apb;
  bit selected_valid;
  int selected;
  logic selected_ready, selected_error;
  logic [15:0] selected_rdata;

  initial begin
    strict_apb = $test$plusargs("STRICT_APB");
    if ($value$plusargs("UVM_TESTNAME=%s", test_name))
      if (test_name == "bridge_strict_apb_test") strict_apb = 1;
  end

  always @(axi.mon_cb) begin
    if (axi.mon_cb.resetn !== 1'b1) begin
      aw_stalled = 0;
      w_stalled = 0;
      ar_stalled = 0;
      b_stalled = 0;
      r_stalled = 0;
      previous_setup = 0;
      previous_wait = 0;
      previous_completion = 0;
    end else begin
      if ($isunknown({axi.mon_cb.awvalid, axi.mon_cb.awready,
                      axi.mon_cb.wvalid, axi.mon_cb.wready,
                      axi.mon_cb.bvalid, axi.mon_cb.bready,
                      axi.mon_cb.arvalid, axi.mon_cb.arready,
                      axi.mon_cb.rvalid, axi.mon_cb.rready}))
        `uvm_error("AXI_X", "AXI handshake control contains X/Z")

      if (aw_stalled && (axi.mon_cb.awvalid !== 1'b1 ||
          {axi.mon_cb.awaddr, axi.mon_cb.awprot} !== last_aw))
        `uvm_error("AXI_AW_STABLE", "AWVALID/address/protection changed while stalled")
      if (w_stalled && (axi.mon_cb.wvalid !== 1'b1 ||
          {axi.mon_cb.wdata, axi.mon_cb.wstrb} !== last_w))
        `uvm_error("AXI_W_STABLE", "WVALID/data/strobes changed while stalled")
      if (ar_stalled && (axi.mon_cb.arvalid !== 1'b1 ||
          {axi.mon_cb.araddr, axi.mon_cb.arprot} !== last_ar))
        `uvm_error("AXI_AR_STABLE", "ARVALID/address/protection changed while stalled")
      if (b_stalled && (axi.mon_cb.bvalid !== 1'b1 ||
          axi.mon_cb.bresp !== last_b))
        `uvm_error("AXI_B_STABLE", "BVALID/response changed while stalled")
      if (r_stalled && (axi.mon_cb.rvalid !== 1'b1 ||
          {axi.mon_cb.rdata, axi.mon_cb.rresp} !== last_r))
        `uvm_error("AXI_R_STABLE", "RVALID/data/response changed while stalled")

      if (axi.mon_cb.awvalid === 1'b1 &&
          $isunknown({axi.mon_cb.awaddr, axi.mon_cb.awprot}))
        `uvm_error("AXI_AW_X", "Valid write address contains X/Z")
      if (axi.mon_cb.wvalid === 1'b1 &&
          $isunknown({axi.mon_cb.wdata, axi.mon_cb.wstrb}))
        `uvm_error("AXI_W_X", "Valid write data/strobes contain X/Z")
      if (axi.mon_cb.arvalid === 1'b1 &&
          $isunknown({axi.mon_cb.araddr, axi.mon_cb.arprot}))
        `uvm_error("AXI_AR_X", "Valid read address contains X/Z")
      if (axi.mon_cb.bvalid === 1'b1 && $isunknown(axi.mon_cb.bresp))
        `uvm_error("AXI_B_X", "Valid write response contains X/Z")
      if (axi.mon_cb.rvalid === 1'b1 &&
          $isunknown({axi.mon_cb.rdata, axi.mon_cb.rresp}))
        `uvm_error("AXI_R_X", "Valid read response contains X/Z")

      aw_stalled = axi.mon_cb.awvalid === 1'b1 && axi.mon_cb.awready !== 1'b1;
      w_stalled  = axi.mon_cb.wvalid  === 1'b1 && axi.mon_cb.wready  !== 1'b1;
      ar_stalled = axi.mon_cb.arvalid === 1'b1 && axi.mon_cb.arready !== 1'b1;
      b_stalled  = axi.mon_cb.bvalid  === 1'b1 && axi.mon_cb.bready  !== 1'b1;
      r_stalled  = axi.mon_cb.rvalid  === 1'b1 && axi.mon_cb.rready  !== 1'b1;
      last_aw = {axi.mon_cb.awaddr, axi.mon_cb.awprot};
      last_w  = {axi.mon_cb.wdata, axi.mon_cb.wstrb};
      last_ar = {axi.mon_cb.araddr, axi.mon_cb.arprot};
      last_b  = axi.mon_cb.bresp;
      last_r  = {axi.mon_cb.rdata, axi.mon_cb.rresp};

      selected_valid = 1;
      case (apb.mon_cb.psel)
        3'b001: selected = 0;
        3'b010: selected = 1;
        3'b100: selected = 2;
        default: begin selected = 0; selected_valid = 0; end
      endcase
      if (!selected_valid && apb.mon_cb.psel !== 3'b000)
        `uvm_error("APB_SELECT", "PSEL must be known and one-hot or zero")
      if ($isunknown(apb.mon_cb.penable))
        `uvm_error("APB_ENABLE_X", "PENABLE contains X/Z")

      selected_ready = apb.mon_cb.pready[selected];
      selected_error = apb.mon_cb.pslverr[selected];
      case (selected)
        0: selected_rdata = apb.mon_cb.prdata_uart;
        1: selected_rdata = apb.mon_cb.prdata_gpio;
        2: selected_rdata = apb.mon_cb.prdata_timer;
      endcase
      // Width is 32 + 3 + 1 + 16 + 2 + 3 = 57 bits.
      current_apb = {apb.mon_cb.paddr, apb.mon_cb.psel, apb.mon_cb.pwrite,
                     apb.mon_cb.pwdata, apb.mon_cb.pstrb, apb.mon_cb.pprot};

      if (previous_setup && (!selected_valid || apb.mon_cb.penable !== 1'b1 ||
                             current_apb !== last_apb))
        `uvm_error("APB_SETUP", "SETUP must advance to ACCESS with stable request")
      if (previous_wait && (!selected_valid || apb.mon_cb.penable !== 1'b1 ||
                            current_apb !== last_apb))
        `uvm_error("APB_WAIT_STABLE", "APB request changed during an ACCESS wait")
      if (previous_completion && apb.mon_cb.penable !== 1'b0)
        `uvm_error("APB_END", "PENABLE must fall following a completed transfer")
      if (selected_valid && apb.mon_cb.penable === 1'b1 &&
          !previous_setup && !previous_wait)
        `uvm_error("APB_PHASE", "ACCESS has no preceding SETUP or waiting ACCESS")

      if (selected_valid) begin
        if ($isunknown(current_apb))
          `uvm_error("APB_REQUEST_X", "Selected APB request contains X/Z")
        // PPROT carries the accepted AxPROT (fixed RTL: assign PPROT =
        // apb_prot). Its value is compared against the AXI request per
        // transaction by bridge_scoreboard (APB_PROT). This checker only
        // guarantees it is known (APB_REQUEST_X above) and stable from SETUP
        // to completion (pprot is part of current_apb). The former
        // constant-zero rule belonged to the original RTL and was removed.
        if (strict_apb && apb.mon_cb.pwrite === 1'b0 &&
            apb.mon_cb.pstrb !== 2'b00)
          `uvm_error("APB_READ_STRB", "APB4 requires PSTRB=0 on reads; original RTL retains write strobes")
        if (apb.mon_cb.penable === 1'b1) begin
          if ($isunknown(selected_ready))
            `uvm_error("APB_READY_X", "Selected PREADY contains X/Z")
          if (selected_ready === 1'b1 && $isunknown(selected_error))
            `uvm_error("APB_ERROR_X", "Completing transfer has unknown PSLVERR")
          if (selected_ready === 1'b1 && apb.mon_cb.pwrite === 1'b0 &&
              $isunknown(selected_rdata))
            `uvm_error("APB_DATA_X", "Completing read has unknown PRDATA")
        end
      end
      // The exposed PSEL vector excludes unmapped addresses. An unmapped
      // access raises no PSEL_* and the wrapper's default sink ends it with
      // SLVERR, so this checker never tracks it.
      previous_setup = selected_valid && apb.mon_cb.penable === 1'b0;
      previous_wait = selected_valid && apb.mon_cb.penable === 1'b1 &&
                      selected_ready !== 1'b1;
      previous_completion = selected_valid && apb.mon_cb.penable === 1'b1 &&
                            selected_ready === 1'b1;
      last_apb = current_apb;
    end
  end
endmodule

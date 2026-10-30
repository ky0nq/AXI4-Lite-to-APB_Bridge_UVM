`timescale 1ns/1ps
package bridge_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  // Components own their inline methods; sequences and tests are grouped.
  // Include these here once; compile bridge_pkg.sv after the interfaces.
  `include "bridge_cfg.sv"
  `include "axi_item.sv"
  `include "apb_item.sv"

  `include "axi_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_coverage.sv"
  `include "axi_agent.sv"
  `include "apb_responder.sv"
  `include "apb_monitor.sv"
  `include "apb_coverage.sv"
  `include "apb_agent.sv"

  // bridge_coverage reuses the imp classes that bridge_scoreboard declares.
  `include "bridge_scoreboard.sv"
  `include "bridge_coverage.sv"
  `include "bridge_env.sv"

  `include "bridge_sequence.sv"
  `include "bridge_test.sv"
endpackage

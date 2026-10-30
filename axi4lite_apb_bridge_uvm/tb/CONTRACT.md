# Internal testbench contract

Agent, driver, responder, monitor, coverage, scoreboard, environment,
configuration, and transaction classes each have their own same-named .sv file.
The five sequence classes are grouped in bridge_sequence.sv, and the six test
classes are grouped in bridge_test.sv. All tasks and functions remain defined
inline inside their classes. There are no project .svh files. Interfaces remain
in tb/interfaces, and bridge_protocol_checker.sv remains a separate module.

Compile order: RTL -> interfaces -> bridge_pkg.sv -> bridge_protocol_checker.sv
-> tb_top.sv. The package imports uvm_pkg and includes the class .sv files in this
dependency order:
bridge_cfg, axi_item, apb_item -> axi_driver, axi_monitor, axi_agent ->
apb_responder, apb_monitor, apb_coverage, apb_agent -> bridge_scoreboard ->
bridge_env -> bridge_sequence.sv -> bridge_test.sv.

Class order in bridge_sequence.sv: bridge_sequence_base, bridge_smoke_sequence,
bridge_error_sequence, bridge_random_sequence, bridge_single_sequence.
Class order in bridge_test.sv: bridge_base_test, bridge_smoke_test,
bridge_stress_test, bridge_reset_test, bridge_strict_apb_test, bridge_unmapped_test.

Do not also compile the included class files separately. Keep each base class
before its derived classes. The three uvm_analysis_imp_decl macros must precede
bridge_scoreboard at package scope. Existing class names and behavior are
preserved; functional coverage now has an explicit apb_coverage subscriber.

uvm_macros.svh remains an external, standard UVM 1.2 library include. It is the
library's macro header, not a project source split. The simulator must provide
uvm_pkg and the UVM include path.

Interfaces (all input logic clk, resetn): axi_lite_if and apb_if. Both expose
clocking mon_cb @(posedge clk), default input #1step; all signals inputs.
Drivers drive interface signals directly only at negedge clk, observe handshakes
at @(vif.mon_cb). Initial idle assignments at time zero permitted.
axi_lite_if: awaddr[31:0], awprot[2:0], awvalid, awready, wdata[31:0],
wstrb[3:0], wvalid,wready,bresp[1:0],bvalid,bready, araddr[31:0],arprot[2:0],
arvalid,arready,rdata[31:0],rresp[1:0],rvalid,rready.
apb_if: paddr[31:0], psel[2:0] (0 UART,1 GPIO,2 TIMER), penable,pwrite,
pwdata[15:0],pstrb[1:0],pprot[2:0], pready[2:0],pslverr[2:0],
prdata_uart[15:0],prdata_gpio[15:0],prdata_timer[15:0].
bridge_reset_if(input logic clk): logic resetn=0; task apply_reset(int cycles=5).

bridge_cfg extends uvm_object, fields: virtual axi_lite_if axi_vif;
virtual apb_if apb_vif; virtual bridge_reset_if rst_vif;
int unsigned timeout_cycles=200, apb_min_wait=0, apb_max_wait=5;
bit enable_error=0; bit [31:0] error_mask=32'h100,error_match=32'h100;
bit strict_apb=0; int unsigned num_random=100;
cfg is set at uvm_test_top then test forwards config_db #(bridge_cfg)::set(this,"*","cfg",cfg).
Every component obtains cfg via config_db get(this,"","cfg",cfg).

axi_item extends uvm_sequence_item: rand bit write; rand bit[31:0] addr,data;
rand bit[3:0] strb; rand bit[2:0] prot; rand int unsigned aw_delay,w_delay,
ar_delay,response_delay; logic[1:0] resp; logic[31:0] rdata; bit aborted;
Constraints: addr[0]==0; addr[14:12] inside {1,3,5}; addr[31:16]==16'h4000;
addr[11:9]==0; addr[15]==0; delays 0..6,response_delay 0..10;
strobes limited selected halfword (addr[1]? strb[1:0]==0:strb[3:2]==0).
Request monitor publishes an axi_item on completed AW+W pair or AR handshake;
response monitor publishes complete axi_item on B/R handshake, maintaining queues.
axi_agent: axi_driver drv; uvm_sequencer#(axi_item) seqr; axi_monitor mon;
mon.req_ap and mon.rsp_ap: uvm_analysis_port#(axi_item).
Driver edits response fields of original request (no put_response).
One sequence item in flight at a time; independent AW/W valid start and hold
through individual handshakes. response_delay counts cycles after BVALID/RVALID.
Reset aborts current item, idle outputs, item_done; no stale transactions.

apb_item extends uvm_sequence_item: logic[31:0] addr; logic write;
logic[15:0] data,rdata; logic[1:0] strb; logic[2:0] prot,sel;
logic error; int unsigned wait_cycles.
apb_agent: apb_responder drv; apb_monitor mon; apb_coverage cov;
mon.ap analysis_port#(apb_item).
apb_coverage extends uvm_subscriber#(apb_item) and samples completed transfers
in its inline write(apb_item) function. The monitor only observes and publishes;
bridge_env connects apb.mon.ap to both scb.apb_imp and apb.cov.analysis_export.
Responder memory uses bit[31:0] key={paddr[31:1],1'b0}; default zero.
Updates selected bytes only on successful completed write; clears on reset.
Error iff cfg.enable_error && (paddr & error_mask)==error_match;
error reads return memory contents, failed writes don't update memory.
Sample config per setup; random wait in configured min..max. Unselected
slaves drive distinguishable poison read data/error/ready to exercise mux.
Responder captures setup at negedge then drives response for next posedge;
updates memory from completion sampled mon_cb (avoid races and off-by-one).

bridge_scoreboard uses analysis_imp_decl(_axi_req),(_axi_rsp),(_apb).
Public ports axi_req_imp,axi_rsp_imp,apb_imp; reset watcher flushes queues/memory;
compares observed AXI requests to observed APB and then AXI responses,
independent memory reference; preserves X detection with case comparisons.
Port ordering across monitors must not affect correctness (queues or FIFOs).
bridge_env fields axi_agent axi; apb_agent apb; bridge_scoreboard scb.
Test names bridge_smoke_test,bridge_stress_test,bridge_reset_test,
bridge_strict_apb_test (intentional original RTL protocol failure),
bridge_unmapped_test (intentional timeout, use address 32'h4000_0000).
Base test provides cfg,env, drives initial reset with cfg.rst_vif.
No original RTL behavior fixes; PPROT is constant zero, read PSTRB stale.
Only strict test flags nonzero read PSTRB; documented as original APB4 defect.

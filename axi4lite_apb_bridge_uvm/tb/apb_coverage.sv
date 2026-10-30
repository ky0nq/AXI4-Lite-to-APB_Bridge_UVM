// Functional coverage is an analysis subscriber. apb_monitor publishes each
// completed transfer once; bridge_env connects that stream to analysis_export.
class apb_coverage extends uvm_subscriber #(apb_item);
  `uvm_component_utils(apb_coverage)
  int unsigned samples_received = 0;
  int unsigned samples_covered = 0;

  covergroup transfer_cg with function sample(
      bit [2:0] slave, bit direction, bit lane, bit [1:0] strobes,
      int unsigned waits, bit err);
    option.per_instance = 1;
    cp_slave: coverpoint slave {
      bins uart = {3'b001}; bins gpio = {3'b010}; bins timer = {3'b100};
    }
    cp_direction: coverpoint direction { bins read = {0}; bins write = {1}; }
    cp_lane: coverpoint lane { bins low_half = {0}; bins high_half = {1}; }
    // Read PSTRB is stale in the upstream RTL. Only writes can satisfy
    // byte-enable coverage; a read must not inflate these bins or the cross.
    cp_strobes: coverpoint strobes iff (direction) {
      bins no_bytes = {0}; bins low_byte = {1};
      bins high_byte = {2}; bins both_bytes = {3};
    }
    cp_wait: coverpoint waits {
      bins zero = {0}; bins one = {1}; bins short_wait = {[2:3]};
      bins long_wait = {[4:15]}; bins extended_wait = {[16:32'hffff_ffff]};
    }
    cp_error: coverpoint err { bins okay = {0}; bins slverr = {1}; }
    slave_direction: cross cp_slave, cp_direction;
    lane_strobes: cross cp_lane, cp_strobes;
    slave_error: cross cp_slave, cp_error;
    direction_wait: cross cp_direction, cp_wait;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    transfer_cg = new();
  endfunction

  function void write(apb_item t);
    samples_received++;
    if (!$isunknown({t.sel, t.write, t.addr[1],
                     t.strb, t.error})) begin
      transfer_cg.sample(t.sel, t.write, t.addr[1],
                         t.strb, t.wait_cycles, t.error);
      samples_covered++;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("APB_COVERAGE",
              $sformatf("received=%0d sampled=%0d", samples_received,
                        samples_covered), UVM_LOW)
  endfunction
endclass


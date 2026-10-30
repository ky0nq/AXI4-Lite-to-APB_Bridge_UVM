// AXI-side functional coverage. apb_coverage only sees requests that became
// an APB transfer; rejected and unmapped-decode requests complete
// with SLVERR straight from the bridge and are visible here only.
// axi_monitor.rsp_ap publishes each completed request with its B/R response;
// reset-aborted requests never complete and are counted by the scoreboard.
class axi_coverage extends uvm_subscriber #(axi_item);
  `uvm_component_utils(axi_coverage)
  int unsigned samples_received = 0;
  int unsigned samples_covered = 0;

  // Why the response ended as it did. Priority matches
  // bridge_scoreboard::rejected_request: decode, alignment, lane, PSLVERR.
  localparam bit [2:0] CAUSE_OKAY       = 3'd0;
  localparam bit [2:0] CAUSE_UNMAPPED   = 3'd1;
  localparam bit [2:0] CAUSE_MISALIGNED = 3'd2;
  localparam bit [2:0] CAUSE_LANE       = 3'd3;
  localparam bit [2:0] CAUSE_PSLVERR    = 3'd4;

  covergroup response_cg with function sample(
      bit direction, bit [1:0] resp, bit [2:0] decode, bit [2:0] cause,
      bit [2:0] prot, bit lane);
    option.per_instance = 1;
    cp_direction: coverpoint direction { bins read = {0}; bins write = {1}; }
    cp_resp: coverpoint resp { bins okay = {2'b00}; bins slverr = {2'b10}; }
    // PADDR[14:12]: 1/2/3 are UART/GPIO/TIMER, every other code is unmapped.
    cp_decode: coverpoint decode {
      bins uart = {3'd1}; bins gpio = {3'd2}; bins timer = {3'd3};
      bins unmapped = {3'd0, [3'd4:3'd7]};
    }
    cp_cause: coverpoint cause {
      bins okay = {CAUSE_OKAY}; bins unmapped = {CAUSE_UNMAPPED};
      bins misaligned = {CAUSE_MISALIGNED}; bins lane = {CAUSE_LANE};
      bins pslverr = {CAUSE_PSLVERR};
    }
    cp_prot: coverpoint prot { bins value[] = {[0:7]}; }
    cp_lane: coverpoint lane { bins low_half = {0}; bins high_half = {1}; }
    direction_resp: cross cp_direction, cp_resp;
    direction_decode: cross cp_direction, cp_decode;
    // A read has no strobes, so it can never be a lane reject.
    direction_cause: cross cp_direction, cp_cause {
      ignore_bins read_lane = binsof(cp_direction.read) && binsof(cp_cause.lane);
    }
    direction_prot: cross cp_direction, cp_prot;
    direction_lane: cross cp_direction, cp_lane;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    response_cg = new();
  endfunction

  function bit [2:0] response_cause(axi_item t);
    if (!(t.addr[14:12] inside {3'd1, 3'd2, 3'd3})) return CAUSE_UNMAPPED;
    if (t.addr[0]) return CAUSE_MISALIGNED;
    if (t.write && (t.addr[1] ? t.strb[1:0] != 2'b00 : t.strb[3:2] != 2'b00))
      return CAUSE_LANE;
    if (t.resp == 2'b10) return CAUSE_PSLVERR;
    return CAUSE_OKAY;
  endfunction

  function void write(axi_item t);
    samples_received++;
    if (!$isunknown({t.write, t.addr, t.strb, t.prot, t.resp})) begin
      response_cg.sample(t.write, t.resp, t.addr[14:12], response_cause(t),
                         t.prot, t.addr[1]);
      samples_covered++;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_COVERAGE",
              $sformatf("received=%0d sampled=%0d response_cg=%0.1f%%",
                        samples_received, samples_covered,
                        response_cg.get_inst_coverage()), UVM_LOW)
  endfunction
endclass

// Bridge-level functional coverage. axi_coverage and apb_coverage each see one
// bus; this collector subscribes to both monitors, next to the scoreboard, and
// covers what only the pairing shows: how each request ended, what came right
// before it, whether a read followed a write to the same halfword, and at which
// stage reset aborted a request.
//
// Observation only, no reference model. The TB allows ONE outstanding request,
// so pairing is a single slot: AXI request -> optional APB transfer -> AXI
// response. The bridge raises B/R at least one clock after the APB transfer
// completes, so the APB observation always arrives before the response.
// The _axi_req/_axi_rsp/_apb imp classes are declared in bridge_scoreboard.sv.
class bridge_coverage extends uvm_component;
  `uvm_component_utils(bridge_coverage)

  uvm_analysis_imp_axi_req #(axi_item, bridge_coverage) axi_req_imp;
  uvm_analysis_imp_axi_rsp #(axi_item, bridge_coverage) axi_rsp_imp;
  uvm_analysis_imp_apb #(apb_item, bridge_coverage) apb_imp;
  bridge_cfg cfg;
  int unsigned samples_received = 0;

  localparam bit [1:0] OUT_OKAY     = 2'd0; // APB transfer, OKAY
  localparam bit [1:0] OUT_PSLVERR  = 2'd1; // APB transfer with PSLVERR, SLVERR
  localparam bit [1:0] OUT_REJECTED = 2'd2; // SLVERR without an APB transfer

  localparam bit STAGE_PENDING_APB      = 1'b0; // accepted, no APB transfer yet
  localparam bit STAGE_PENDING_RESPONSE = 1'b1; // APB transfer done, no B/R yet

  localparam bit [1:0] HIST_FRESH       = 2'd0;
  localparam bit [1:0] HIST_AFTER_WRITE = 2'd1;
  localparam bit [1:0] HIST_AFTER_ERROR = 2'd2;

  // The one in-flight request.
  bit pending;
  bit pending_write;
  bit [31:0] pending_addr;
  bit saw_apb;
  bit [2:0] apb_sel;

  // History is cleared on reset, like the bridge and the APB models.
  bit have_prev;
  bit prev_write;
  bit [2:0] prev_slave;
  // Last completed APB write per halfword: HIST_AFTER_WRITE or HIST_AFTER_ERROR.
  bit [1:0] last_write[bit [31:0]];

  covergroup outcome_cg with function sample(bit direction, bit [1:0] outcome);
    option.per_instance = 1;
    cp_direction: coverpoint direction { bins read = {0}; bins write = {1}; }
    cp_outcome: coverpoint outcome {
      bins okay = {OUT_OKAY}; bins pslverr = {OUT_PSLVERR};
      bins rejected = {OUT_REJECTED};
    }
    direction_outcome: cross cp_direction, cp_outcome;
  endgroup

  // Back-to-back pairs. B01 was a write-accept to read boundary, so every
  // direction pair and every peripheral pair must occur in sequence.
  // Slave 000 (rejected, no APB transfer) has no bin and is not counted.
  covergroup transition_cg with function sample(bit prev_dir, bit cur_dir,
                                                 bit [2:0] prev_sl, bit [2:0] cur_sl);
    option.per_instance = 1;
    cp_prev_dir: coverpoint prev_dir { bins read = {0}; bins write = {1}; }
    cp_cur_dir: coverpoint cur_dir { bins read = {0}; bins write = {1}; }
    cp_prev_slave: coverpoint prev_sl {
      bins uart = {3'b001}; bins gpio = {3'b010}; bins timer = {3'b100};
    }
    cp_cur_slave: coverpoint cur_sl {
      bins uart = {3'b001}; bins gpio = {3'b010}; bins timer = {3'b100};
    }
    direction_transition: cross cp_prev_dir, cp_cur_dir;
    slave_transition: cross cp_prev_slave, cp_cur_slave;
  endgroup

  // APB reads by what was last written to the same halfword since reset.
  covergroup read_history_cg with function sample(bit [1:0] history);
    option.per_instance = 1;
    cp_history: coverpoint history {
      bins fresh = {HIST_FRESH};
      bins after_write = {HIST_AFTER_WRITE};
      bins after_error_write = {HIST_AFTER_ERROR};
    }
  endgroup

  covergroup abort_cg with function sample(bit direction, bit stage);
    option.per_instance = 1;
    cp_direction: coverpoint direction { bins read = {0}; bins write = {1}; }
    cp_stage: coverpoint stage {
      bins pending_apb = {STAGE_PENDING_APB};
      bins pending_response = {STAGE_PENDING_RESPONSE};
    }
    direction_stage: cross cp_direction, cp_stage;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    axi_req_imp = new("axi_req_imp", this);
    axi_rsp_imp = new("axi_rsp_imp", this);
    apb_imp = new("apb_imp", this);
    outcome_cg = new();
    transition_cg = new();
    read_history_cg = new();
    abort_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "bridge_coverage requires bridge_cfg")
  endfunction

  function void write_axi_req(axi_item t);
    if (cfg.axi_vif.resetn !== 1'b1) return;
    pending = 1;
    pending_write = t.write;
    pending_addr = t.addr;
    saw_apb = 0;
    apb_sel = 3'b000;
  endfunction

  function void write_apb(apb_item t);
    if (cfg.axi_vif.resetn !== 1'b1 || !pending) return;
    saw_apb = 1;
    apb_sel = t.sel;
  endfunction

  function void write_axi_rsp(axi_item t);
    bit [1:0] outcome;
    bit [31:0] key;
    if (cfg.axi_vif.resetn !== 1'b1 || !pending || $isunknown(t.resp)) return;
    samples_received++;
    if (!saw_apb) outcome = OUT_REJECTED;
    else if (t.resp == 2'b10) outcome = OUT_PSLVERR;
    else outcome = OUT_OKAY;
    key = {pending_addr[31:1], 1'b0};

    outcome_cg.sample(pending_write, outcome);
    if (have_prev)
      transition_cg.sample(prev_write, pending_write, prev_slave, apb_sel);
    if (!pending_write && saw_apb)
      read_history_cg.sample(last_write.exists(key) ? last_write[key] : HIST_FRESH);
    if (pending_write && saw_apb)
      last_write[key] = (outcome == OUT_OKAY) ? HIST_AFTER_WRITE : HIST_AFTER_ERROR;
    prev_write = pending_write;
    prev_slave = apb_sel;
    have_prev = 1;
    pending = 0;
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(negedge cfg.axi_vif.resetn);
      if (pending)
        abort_cg.sample(pending_write, saw_apb ? STAGE_PENDING_RESPONSE
                                               : STAGE_PENDING_APB);
      pending = 0;
      have_prev = 0;
      last_write.delete();
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("BRIDGE_COVERAGE",
              $sformatf("responses=%0d outcome=%0.1f%% transition=%0.1f%% read_history=%0.1f%% abort=%0.1f%%",
                        samples_received, outcome_cg.get_inst_coverage(),
                        transition_cg.get_inst_coverage(),
                        read_history_cg.get_inst_coverage(),
                        abort_cg.get_inst_coverage()), UVM_LOW)
  endfunction
endclass

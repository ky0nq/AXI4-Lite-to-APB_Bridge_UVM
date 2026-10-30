class bridge_env extends uvm_env;
  `uvm_component_utils(bridge_env)
  bridge_cfg cfg;
  axi_agent axi;
  apb_agent apb;
  bridge_scoreboard scb;
  bridge_coverage cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "bridge_env requires bridge_cfg")
    axi = axi_agent::type_id::create("axi", this);
    apb = apb_agent::type_id::create("apb", this);
    scb = bridge_scoreboard::type_id::create("scb", this);
    cov = bridge_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    axi.mon.req_ap.connect(scb.axi_req_imp);
    axi.mon.rsp_ap.connect(scb.axi_rsp_imp);
    axi.mon.rsp_ap.connect(axi.cov.analysis_export);
    apb.mon.ap.connect(scb.apb_imp);
    apb.mon.ap.connect(apb.cov.analysis_export);
    axi.mon.req_ap.connect(cov.axi_req_imp);
    axi.mon.rsp_ap.connect(cov.axi_rsp_imp);
    apb.mon.ap.connect(cov.apb_imp);
  endfunction
endclass

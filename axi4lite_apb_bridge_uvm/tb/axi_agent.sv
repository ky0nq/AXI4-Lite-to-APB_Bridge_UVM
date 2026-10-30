class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  bridge_cfg cfg;
  axi_driver drv;
  uvm_sequencer #(axi_item) seqr;
  axi_monitor mon;
  axi_coverage cov;

  function new(string name = "axi_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_CFG", "bridge_cfg was not supplied to axi_agent")
    if (cfg == null)
      `uvm_fatal("AXI_CFG", "axi_agent received a null bridge_cfg")
    mon = axi_monitor::type_id::create("mon", this);
    cov = axi_coverage::type_id::create("cov", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv = axi_driver::type_id::create("drv", this);
      seqr = uvm_sequencer #(axi_item)::type_id::create("seqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass


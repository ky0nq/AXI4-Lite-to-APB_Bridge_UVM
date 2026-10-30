class apb_agent extends uvm_agent;
  `uvm_component_utils(apb_agent)
  apb_responder drv;
  apb_monitor mon;
  apb_coverage cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = apb_responder::type_id::create("drv", this);
    mon = apb_monitor::type_id::create("mon", this);
    cov = apb_coverage::type_id::create("cov", this);
  endfunction
endclass
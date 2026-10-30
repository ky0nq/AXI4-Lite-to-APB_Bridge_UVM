// The corrected bridge keeps the original 32/32/16 halfword register contract.
class bridge_cfg extends uvm_object;
  `uvm_object_utils(bridge_cfg)
  virtual axi_lite_if axi_vif;
  virtual apb_if apb_vif;
  int unsigned timeout_cycles = 200;
  int unsigned apb_min_wait = 0;
  int unsigned apb_max_wait = 5;
  bit enable_error = 0;
  bit [31:0] error_mask = 32'h0000_0100;
  bit [31:0] error_match = 32'h0000_0100;
  bit strict_apb = 1;
  int unsigned num_random = 100;
  function new(string name = "bridge_cfg");
    super.new(name);
  endfunction
endclass

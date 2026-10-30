class apb_item extends uvm_sequence_item;
  logic [31:0] addr;
  logic write;
  logic [15:0] data, rdata;
  logic [1:0] strb;
  logic [2:0] prot, sel;
  logic error;
  int unsigned wait_cycles;
  `uvm_object_utils_begin(apb_item)
    `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(write, UVM_DEFAULT)
    `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(rdata, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(strb, UVM_DEFAULT)
    `uvm_field_int(prot, UVM_DEFAULT)
    `uvm_field_int(sel, UVM_DEFAULT)
    `uvm_field_int(error, UVM_DEFAULT)
    `uvm_field_int(wait_cycles, UVM_DEFAULT)
  `uvm_object_utils_end
  function new(string name = "apb_item");
    super.new(name);
  endfunction
endclass

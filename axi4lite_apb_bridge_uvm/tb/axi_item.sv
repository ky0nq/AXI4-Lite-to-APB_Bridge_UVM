class axi_item extends uvm_sequence_item;
  rand bit write;
  rand bit [31:0] addr, data;
  rand bit [3:0] strb;
  rand bit [2:0] prot;
  rand int unsigned aw_delay, w_delay, ar_delay, response_delay;
  logic [1:0] resp;
  logic [31:0] rdata;
  bit aborted = 0;
  // Set by axi_driver when the item completes or is reset-aborted. Not a
  // field: monitors and the scoreboard never copy or compare it.
  bit done = 0;

  constraint c_address {
    addr[0] == 0;
    addr[14:12] inside {3'd1, 3'd2, 3'd3}; // UART, GPIO, TIMER
    addr[31:16] == 16'h4000;
    addr[15] == 0;
    addr[11:9] == 0;
  }
  constraint c_strobes {
    if (addr[1]) strb[1:0] == 0;
    else strb[3:2] == 0;
  }
  constraint c_delay {
    aw_delay inside {[0:6]};
    w_delay inside {[0:6]};
    ar_delay inside {[0:6]};
    response_delay inside {[0:10]};
  }

  `uvm_object_utils_begin(axi_item)
    `uvm_field_int(write, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(strb, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(prot, UVM_DEFAULT)
    `uvm_field_int(aw_delay, UVM_DEFAULT)
    `uvm_field_int(w_delay, UVM_DEFAULT)
    `uvm_field_int(ar_delay, UVM_DEFAULT)
    `uvm_field_int(response_delay, UVM_DEFAULT)
    `uvm_field_int(resp, UVM_DEFAULT)
    `uvm_field_int(rdata, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(aborted, UVM_DEFAULT)
  `uvm_object_utils_end
  function new(string name = "axi_item");
    super.new(name);
  endfunction
endclass

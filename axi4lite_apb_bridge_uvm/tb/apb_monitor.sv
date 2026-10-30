class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)

  bridge_cfg cfg;
  virtual apb_if vif;
  uvm_analysis_port#(apb_item) ap;
  int unsigned wait_cycles;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "apb_monitor requires bridge_cfg")
    vif = cfg.apb_vif;
    if (vif == null)
      `uvm_fatal("NO_VIF", "apb_monitor requires apb_vif")
  endfunction

  task run_phase(uvm_phase phase);
    apb_item item;
    int selected;
    wait_cycles = 0;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.resetn !== 1'b1) begin
        wait_cycles = 0;
        continue;
      end
      case (vif.mon_cb.psel)
        3'b001: selected = 0;
        3'b010: selected = 1;
        3'b100: selected = 2;
        default: selected = -1;
      endcase
      if (selected < 0) begin
        wait_cycles = 0;
        continue;
      end
      if (vif.mon_cb.penable === 1'b0) begin
        wait_cycles = 0;
      end else if (vif.mon_cb.penable === 1'b1) begin
        if (vif.mon_cb.pready[selected] === 1'b0) begin
          wait_cycles++;
        end else if (vif.mon_cb.pready[selected] === 1'b1) begin
          item = apb_item::type_id::create("observed_apb", this);
          item.addr = vif.mon_cb.paddr;
          item.write = vif.mon_cb.pwrite;
          item.data = vif.mon_cb.pwdata;
          item.strb = vif.mon_cb.pstrb;
          item.prot = vif.mon_cb.pprot;
          item.sel = vif.mon_cb.psel;
          item.error = vif.mon_cb.pslverr[selected];
          item.wait_cycles = wait_cycles;
          case (selected)
            0: item.rdata = vif.mon_cb.prdata_uart;
            1: item.rdata = vif.mon_cb.prdata_gpio;
            2: item.rdata = vif.mon_cb.prdata_timer;
          endcase
          ap.write(item);
          wait_cycles = 0;
        end
      end
    end
  endtask
endclass


// An AXI4-Lite master with independent write (AW/W/B) and read (AR/R)
// engines. Each engine drives only its own channel signals, so one write and
// one read may be in flight together (bridge_overlap_test). AW and W are
// launched independently; a channel remains valid until its own handshake,
// including while the other channel is delayed. No assumption is made that
// AWREADY and WREADY coincide.
//
// item_done is called as soon as an engine takes the item, so the sequencer
// can hand over an item for the other direction. The sequence keeps its
// one-outstanding view by waiting for item.done (bridge_sequence_base).
class axi_driver extends uvm_driver #(axi_item);
  `uvm_component_utils(axi_driver)

  bridge_cfg cfg;
  virtual axi_lite_if vif;
  bit write_busy;
  bit read_busy;

  function new(string name = "axi_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_CFG", "bridge_cfg was not supplied to axi_driver")
    if (cfg == null)
      `uvm_fatal("AXI_CFG", "axi_driver received a null bridge_cfg")
    vif = cfg.axi_vif;
    if (vif == null)
      `uvm_fatal("AXI_VIF", "bridge_cfg.axi_vif is null")
  endfunction

  // Called at time zero or on a falling clock edge only.
  task idle_write();
    vif.awaddr  = '0;
    vif.awprot  = '0;
    vif.awvalid = 1'b0;
    vif.wdata   = '0;
    vif.wstrb   = '0;
    vif.wvalid  = 1'b0;
    vif.bready  = 1'b0;
  endtask

  task idle_read();
    vif.araddr  = '0;
    vif.arprot  = '0;
    vif.arvalid = 1'b0;
    vif.rready  = 1'b0;
  endtask

  task drive_idle();
    idle_write();
    idle_read();
  endtask

  task run_phase(uvm_phase phase);
    axi_item item;
    drive_idle();
    forever begin
      seq_item_port.get_next_item(item);
      // One item per direction: a second write waits for the first to finish.
      if (item.write) begin
        wait (!write_busy);
        write_busy = 1;
      end
      else begin
        wait (!read_busy);
        read_busy = 1;
      end
      fork
        automatic axi_item it = item;
        drive_item(it);
      join_none
      // The sequence owns this handle and inspects resp/rdata/aborted once
      // item.done is set. There is deliberately no response queue.
      seq_item_port.item_done();
    end
  endtask

  task drive_item(axi_item item);
    item.aborted = 0;
    item.resp = 'x;
    item.rdata = 'x;
    if (item.write) begin
      drive_write(item);
      write_busy = 0;
    end
    else begin
      drive_read(item);
      read_busy = 0;
    end
    item.done = 1;
  endtask

  task drive_write(axi_item item);
    int unsigned age;
    int unsigned elapsed;
    int unsigned response_wait;
    bit aw_done;
    bit w_done;
    bit response_seen;

    age = 0;
    elapsed = 0;
    response_wait = 0;
    aw_done = 0;
    w_done = 0;
    response_seen = 0;

    forever begin
      @(negedge vif.clk);
      if (vif.resetn !== 1'b1) begin
        idle_write();
        item.aborted = 1;
        `uvm_info("AXI_ABORT", "Reset aborted the current AXI write", UVM_MEDIUM)
        return;
      end

      vif.awaddr = item.addr;
      vif.awprot = item.prot;
      vif.awvalid = !aw_done && (age >= item.aw_delay);
      vif.wdata = item.data;
      vif.wstrb = item.strb;
      vif.wvalid = !w_done && (age >= item.w_delay);
      // With zero delay READY may precede VALID. A positive delay counts
      // complete sampled cycles in which response VALID was observed.
      vif.bready = (item.response_delay == 0) ||
                   (response_seen && response_wait >= item.response_delay);

      // mon_cb samples one simulator time step before the rising edge. The
      // sampled READY/VALID pair is the pair the DUT accepts at this edge.
      @(vif.mon_cb);
      if (vif.resetn !== 1'b1) begin
        item.aborted = 1;
        @(negedge vif.clk);
        idle_write();
        `uvm_info("AXI_ABORT", "Reset aborted the current AXI write", UVM_MEDIUM)
        return;
      end

      if (vif.mon_cb.awvalid === 1'b1 && vif.mon_cb.awready === 1'b1)
        aw_done = 1;
      if (vif.mon_cb.wvalid === 1'b1 && vif.mon_cb.wready === 1'b1)
        w_done = 1;
      if (vif.mon_cb.bvalid === 1'b1) begin
        response_seen = 1;
        response_wait++;
        if (vif.mon_cb.bready === 1'b1) begin
          if (!aw_done || !w_done)
            `uvm_error("AXI_EARLY_B", "B response arrived before AW and W handshakes")
          item.resp = vif.mon_cb.bresp;
          item.rdata = '0;
          @(negedge vif.clk);
          idle_write();
          return;
        end
      end

      elapsed++;
      if (elapsed >= cfg.timeout_cycles)
        `uvm_fatal("AXI_TIMEOUT", $sformatf(
          "WRITE addr=0x%08h timed out after %0d cycles (AW=%0b W=%0b response_seen=%0b)",
          item.addr, elapsed, aw_done, w_done, response_seen))
      age++;
    end
  endtask

  task drive_read(axi_item item);
    int unsigned age;
    int unsigned elapsed;
    int unsigned response_wait;
    bit ar_done;
    bit response_seen;

    age = 0;
    elapsed = 0;
    response_wait = 0;
    ar_done = 0;
    response_seen = 0;

    forever begin
      @(negedge vif.clk);
      if (vif.resetn !== 1'b1) begin
        idle_read();
        item.aborted = 1;
        `uvm_info("AXI_ABORT", "Reset aborted the current AXI read", UVM_MEDIUM)
        return;
      end

      vif.araddr = item.addr;
      vif.arprot = item.prot;
      vif.arvalid = !ar_done && (age >= item.ar_delay);
      vif.rready = (item.response_delay == 0) ||
                   (response_seen && response_wait >= item.response_delay);

      @(vif.mon_cb);
      if (vif.resetn !== 1'b1) begin
        item.aborted = 1;
        @(negedge vif.clk);
        idle_read();
        `uvm_info("AXI_ABORT", "Reset aborted the current AXI read", UVM_MEDIUM)
        return;
      end

      if (vif.mon_cb.arvalid === 1'b1 && vif.mon_cb.arready === 1'b1)
        ar_done = 1;
      if (vif.mon_cb.rvalid === 1'b1) begin
        response_seen = 1;
        response_wait++;
        if (vif.mon_cb.rready === 1'b1) begin
          if (!ar_done)
            `uvm_error("AXI_EARLY_R", "R response arrived before an AR handshake")
          item.resp = vif.mon_cb.rresp;
          item.rdata = vif.mon_cb.rdata;
          @(negedge vif.clk);
          idle_read();
          return;
        end
      end

      elapsed++;
      if (elapsed >= cfg.timeout_cycles)
        `uvm_fatal("AXI_TIMEOUT", $sformatf(
          "READ addr=0x%08h timed out after %0d cycles (AR=%0b response_seen=%0b)",
          item.addr, elapsed, ar_done, response_seen))
      age++;
    end
  endtask
endclass

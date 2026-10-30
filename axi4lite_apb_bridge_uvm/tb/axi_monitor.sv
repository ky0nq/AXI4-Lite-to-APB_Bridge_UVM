// Passive bus reconstruction: AW and W have independent handshake queues.
// Publish a request only once both write channels have been accepted, then
// retain a separate copy until its matching B/R response is accepted.
class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  bridge_cfg cfg;
  virtual axi_lite_if vif;
  uvm_analysis_port #(axi_item) req_ap;
  uvm_analysis_port #(axi_item) rsp_ap;
  axi_item aw_queue[$];
  axi_item w_queue[$];
  axi_item write_pending[$];
  axi_item read_pending[$];

  function new(string name = "axi_monitor", uvm_component parent = null);
    super.new(name, parent);
    req_ap = new("req_ap", this);
    rsp_ap = new("rsp_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_CFG", "bridge_cfg was not supplied to axi_monitor")
    if (cfg == null)
      `uvm_fatal("AXI_CFG", "axi_monitor received a null bridge_cfg")
    vif = cfg.axi_vif;
    if (vif == null)
      `uvm_fatal("AXI_VIF", "bridge_cfg.axi_vif is null")
  endfunction

  function axi_item copy_request(axi_item source, string name);
    axi_item result;
    result = axi_item::type_id::create(name);
    result.write = source.write;
    result.addr = source.addr;
    result.data = source.data;
    result.strb = source.strb;
    result.prot = source.prot;
    result.aw_delay = source.aw_delay;
    result.w_delay = source.w_delay;
    result.ar_delay = source.ar_delay;
    result.response_delay = source.response_delay;
    result.aborted = 0;
    result.resp = 'x;
    result.rdata = 'x;
    return result;
  endfunction

  function void flush();
    aw_queue.delete();
    w_queue.delete();
    write_pending.delete();
    read_pending.delete();
  endfunction

  task run_phase(uvm_phase phase);
    axi_item aw;
    axi_item wd;
    axi_item request;
    axi_item pending;
    axi_item response;

    forever begin
      @(vif.mon_cb);
      if (vif.resetn !== 1'b1) begin
        flush();
      end
      else begin
        if (vif.mon_cb.awvalid === 1'b1 && vif.mon_cb.awready === 1'b1) begin
          if ($isunknown({vif.mon_cb.awaddr, vif.mon_cb.awprot}))
            `uvm_error("AXI_X_AW", "Unknown AW payload at a handshake")
          aw = axi_item::type_id::create("aw_capture");
          aw.write = 1;
          aw.addr = vif.mon_cb.awaddr;
          aw.prot = vif.mon_cb.awprot;
          aw_queue.push_back(aw);
        end
        if (vif.mon_cb.wvalid === 1'b1 && vif.mon_cb.wready === 1'b1) begin
          if ($isunknown({vif.mon_cb.wdata, vif.mon_cb.wstrb}))
            `uvm_error("AXI_X_W", "Unknown W payload at a handshake")
          wd = axi_item::type_id::create("w_capture");
          wd.write = 1;
          wd.data = vif.mon_cb.wdata;
          wd.strb = vif.mon_cb.wstrb;
          w_queue.push_back(wd);
        end

        while (aw_queue.size() != 0 && w_queue.size() != 0) begin
          aw = aw_queue.pop_front();
          wd = w_queue.pop_front();
          request = copy_request(aw, "write_request");
          request.data = wd.data;
          request.strb = wd.strb;
          pending = copy_request(request, "write_pending");
          write_pending.push_back(pending);
          req_ap.write(request);
        end

        if (vif.mon_cb.arvalid === 1'b1 && vif.mon_cb.arready === 1'b1) begin
          if ($isunknown({vif.mon_cb.araddr, vif.mon_cb.arprot}))
            `uvm_error("AXI_X_AR", "Unknown AR payload at a handshake")
          request = axi_item::type_id::create("read_request");
          request.write = 0;
          request.addr = vif.mon_cb.araddr;
          request.prot = vif.mon_cb.arprot;
          request.resp = 'x;
          request.rdata = 'x;
          pending = copy_request(request, "read_pending");
          read_pending.push_back(pending);
          req_ap.write(request);
        end

        // Requests are processed first to permit a legal response on the same
        // sampled edge. Subscribers never receive handles mutated afterward.
        if (vif.mon_cb.bvalid === 1'b1 && vif.mon_cb.bready === 1'b1) begin
          if (write_pending.size() == 0)
            `uvm_error("AXI_ORPHAN_B", "B handshake has no matching AW/W request")
          else begin
            response = write_pending.pop_front();
            response.resp = vif.mon_cb.bresp;
            response.rdata = '0;
            rsp_ap.write(response);
          end
        end
        if (vif.mon_cb.rvalid === 1'b1 && vif.mon_cb.rready === 1'b1) begin
          if (read_pending.size() == 0)
            `uvm_error("AXI_ORPHAN_R", "R handshake has no matching AR request")
          else begin
            response = read_pending.pop_front();
            response.resp = vif.mon_cb.rresp;
            response.rdata = vif.mon_cb.rdata;
            rsp_ap.write(response);
          end
        end
      end
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (aw_queue.size() || w_queue.size() ||
        write_pending.size() || read_pending.size())
      `uvm_error("AXI_INCOMPLETE", $sformatf(
        "Unfinished traffic: AW=%0d W=%0d B-pending=%0d R-pending=%0d",
        aw_queue.size(), w_queue.size(),
        write_pending.size(), read_pending.size()))
  endfunction
endclass


`uvm_analysis_imp_decl(_axi_req)
`uvm_analysis_imp_decl(_axi_rsp)
`uvm_analysis_imp_decl(_apb)

// The three monitors can publish in any order within a clock tick. Queue every
// observation, then compare only complete pairs. This reference model derives
// memory updates and response data from AXI requests, never from DUT write data.
// The driver may issue one write and one read together, but the DUT accepts
// ONE transaction at a time, so handshake, APB and response order agree.
// Checking only; bridge_coverage subscribes to the same monitor ports.
class bridge_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(bridge_scoreboard)

  uvm_analysis_imp_axi_req #(axi_item, bridge_scoreboard) axi_req_imp;
  uvm_analysis_imp_axi_rsp #(axi_item, bridge_scoreboard) axi_rsp_imp;
  uvm_analysis_imp_apb #(apb_item, bridge_scoreboard) apb_imp;
  bridge_cfg cfg;
  axi_item request_q[$];
  axi_item response_q[$];
  axi_item expected_q[$];
  apb_item apb_q[$];
  bit [15:0] reference_mem[bit [31:0]];

  int unsigned requests_seen, apb_seen, apb_checked, responses_checked;
  int unsigned rejected_requests, rejected_responses, aborted_rejections;
  int unsigned aborted_requests, discarded_apb, discarded_responses;
  int unsigned reset_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    axi_req_imp = new("axi_req_imp", this);
    axi_rsp_imp = new("axi_rsp_imp", this);
    apb_imp = new("apb_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "bridge_scoreboard requires bridge_cfg")
  endfunction

  function void write_axi_req(axi_item item);
    axi_item saved;
    if (cfg.axi_vif.resetn !== 1'b1) return;
    if (!$cast(saved, item.clone()))
      `uvm_fatal("CLONE", "Cannot clone AXI request")
    requests_seen++;
    if (rejected_request(saved)) begin
      // These requests must complete without a peripheral APB transfer.
      // Construct the response directly; never consume an APB observation.
      saved.resp = 2'b10;
      saved.rdata = 32'h0000_0000;
      expected_q.push_back(saved);
      rejected_requests++;
    end else begin
      request_q.push_back(saved);
    end
    drain();
  endfunction

  function void write_axi_rsp(axi_item item);
    axi_item saved;
    if (cfg.axi_vif.resetn !== 1'b1) return;
    if (!$cast(saved, item.clone()))
      `uvm_fatal("CLONE", "Cannot clone AXI response")
    response_q.push_back(saved);
    drain();
  endfunction

  function void write_apb(apb_item item);
    apb_item saved;
    if (cfg.axi_vif.resetn !== 1'b1) return;
    if (!$cast(saved, item.clone()))
      `uvm_fatal("CLONE", "Cannot clone APB transfer")
    apb_seen++;
    if (expected_q.size() != 0 && rejected_request(expected_q[0]))
      `uvm_error("REJECTED_APB", "A rejected AXI request unexpectedly reached an APB peripheral")
    apb_q.push_back(saved);
    drain();
  endfunction

  function bit rejected_request(axi_item req);
    if (decode_select(req.addr) == 3'b000 || req.addr[0]) return 1;
    if (req.write) begin
      if (req.addr[1] && req.strb[1:0] != 2'b00) return 1;
      if (!req.addr[1] && req.strb[3:2] != 2'b00) return 1;
    end
    return 0;
  endfunction

  function bit [2:0] decode_select(bit [31:0] address);
    case (address[14:12])
      3'd1: return 3'b001; // UART
      3'd2: return 3'b010; // GPIO
      3'd3: return 3'b100; // TIMER
      default: return 3'b000;
    endcase
  endfunction

  function void compare_apb(axi_item req, apb_item bus);
    axi_item expected;
    bit [31:0] key;
    bit [15:0] before_data, after_data, write_data;
    bit [1:0] byte_strobes;
    bit error;
    bit [2:0] selected;

    key = {req.addr[31:1], 1'b0};
    before_data = 16'h0000;
    if (reference_mem.exists(key)) before_data = reference_mem[key];
    after_data = before_data;
    write_data = req.addr[1] ? req.data[31:16] : req.data[15:0];
    byte_strobes = req.addr[1] ? req.strb[3:2] : req.strb[1:0];
    selected = decode_select(req.addr);
    error = cfg.enable_error && ((req.addr & cfg.error_mask) == cfg.error_match);

    if (bus.addr !== req.addr)
      `uvm_error("APB_ADDR", $sformatf("AXI address %08h, APB address %08h", req.addr, bus.addr))
    if (bus.write !== req.write)
      `uvm_error("APB_DIR", $sformatf("addr=%08h AXI write=%b APB write=%b", req.addr, req.write, bus.write))
    if (selected == 3'b000 || bus.sel !== selected)
      `uvm_error("APB_SELECT", $sformatf("addr=%08h expected select=%b observed=%b", req.addr, selected, bus.sel))
    if (bus.prot !== req.prot)
      `uvm_error("APB_PROT", $sformatf("addr=%08h expected PPROT=%b observed=%b", req.addr, req.prot, bus.prot))
    if (bus.error !== error)
      `uvm_error("APB_ERROR", $sformatf("addr=%08h expected PSLVERR=%b observed=%b", req.addr, error, bus.error))

    if (req.write) begin
      if (bus.data !== write_data)
        `uvm_error("APB_WDATA", $sformatf("addr=%08h expected PWDATA=%04h observed=%04h", req.addr, write_data, bus.data))
      if (bus.strb !== byte_strobes)
        `uvm_error("APB_STRB", $sformatf("addr=%08h expected PSTRB=%b observed=%b", req.addr, byte_strobes, bus.strb))
      if (!error) begin
        if (byte_strobes[0]) after_data[7:0] = write_data[7:0];
        if (byte_strobes[1]) after_data[15:8] = write_data[15:8];
        reference_mem[key] = after_data;
      end
    end else begin
      if (bus.rdata !== before_data)
        `uvm_error("APB_RDATA", $sformatf("addr=%08h reference memory=%04h APB read=%04h", req.addr, before_data, bus.rdata))
      if (bus.strb !== 2'b00)
        `uvm_error("APB_READ_STRB", $sformatf("APB4 requires read PSTRB=0: addr=%08h PSTRB=%b", req.addr, bus.strb))
    end

    expected = axi_item::type_id::create("expected");
    expected.copy(req);
    expected.resp = error ? 2'b10 : 2'b00;
    expected.rdata = req.addr[1] ? {before_data, 16'h0000} : {16'h0000, before_data};
    expected_q.push_back(expected);
    apb_checked++;
  endfunction

  function void compare_response(axi_item expected, axi_item actual);
    if (actual.write !== expected.write || actual.addr !== expected.addr)
      `uvm_error("AXI_ORDER", $sformatf("expected write=%b addr=%08h, response write=%b addr=%08h", expected.write, expected.addr, actual.write, actual.addr))
    if (actual.resp !== expected.resp)
      `uvm_error("AXI_RESP", $sformatf("addr=%08h expected response=%b observed=%b", expected.addr, expected.resp, actual.resp))
    if (!expected.write && actual.rdata !== expected.rdata)
      `uvm_error("AXI_RDATA", $sformatf("addr=%08h expected RDATA=%08h observed=%08h", expected.addr, expected.rdata, actual.rdata))
    responses_checked++;
    if (rejected_request(expected)) rejected_responses++;
  endfunction

  function void drain();
    axi_item req, expected, actual;
    apb_item bus;
    while (request_q.size() != 0 && apb_q.size() != 0) begin
      req = request_q.pop_front();
      bus = apb_q.pop_front();
      compare_apb(req, bus);
    end
    while (expected_q.size() != 0 && response_q.size() != 0) begin
      expected = expected_q.pop_front();
      actual = response_q.pop_front();
      compare_response(expected, actual);
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(negedge cfg.axi_vif.resetn);
      reset_count++;
      aborted_requests += request_q.size() + expected_q.size();
      foreach (expected_q[i])
        if (rejected_request(expected_q[i])) aborted_rejections++;
      discarded_apb += apb_q.size();
      discarded_responses += response_q.size();
      request_q.delete();
      expected_q.delete();
      response_q.delete();
      apb_q.delete();
      reference_mem.delete();
    end
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    drain();
    if (request_q.size() || apb_q.size() || expected_q.size() || response_q.size())
      `uvm_error("UNMATCHED", $sformatf("Unmatched observations: AXI requests=%0d APB=%0d expected responses=%0d AXI responses=%0d", request_q.size(), apb_q.size(), expected_q.size(), response_q.size()))
    if (responses_checked == 0)
      `uvm_error("VACUOUS_PASS", "No complete AXI request/response transaction was checked")
    if (requests_seen != responses_checked + aborted_requests)
      `uvm_error("REQUEST_ACCOUNTING", $sformatf("requests=%0d checked=%0d reset-aborted=%0d", requests_seen, responses_checked, aborted_requests))
    if (apb_seen != apb_checked + discarded_apb)
      `uvm_error("APB_ACCOUNTING", "Not all observed APB transfers were accounted for")
    if (rejected_requests != rejected_responses + aborted_rejections)
      `uvm_error("REJECTION_ACCOUNTING", "Not all rejected AXI requests completed or were reset-aborted")
    if (discarded_apb || discarded_responses)
      `uvm_error("ORPHAN_ON_RESET", $sformatf("Reset discarded orphan APB=%0d AXI responses=%0d", discarded_apb, discarded_responses))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", $sformatf("AXI requests=%0d APB checked=%0d responses checked=%0d rejected responses=%0d reset-aborted=%0d", requests_seen, apb_checked, responses_checked, rejected_responses, aborted_requests), UVM_LOW)
  endfunction
endclass

class bridge_base_test extends uvm_test;
  `uvm_component_utils(bridge_base_test)
  bridge_cfg cfg;
  bridge_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "tb_top must set bridge_cfg at uvm_test_top")
    if (cfg.axi_vif == null || cfg.apb_vif == null)
      `uvm_fatal("NO_VIF", "AXI and APB virtual interfaces must both be connected")
    configure();
    uvm_config_db#(bridge_cfg)::set(this, "*", "cfg", cfg);
    env = bridge_env::type_id::create("env", this);
  endfunction

  virtual task execute();
    bridge_smoke_sequence seq;
    seq = bridge_smoke_sequence::type_id::create("smoke");
    seq.start(env.axi.seqr);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    cfg.axi_vif.apply_reset(5);
    repeat (2) @(cfg.axi_vif.mon_cb);
    execute();
    // Let all monitor publications settle before check_phase accounts queues.
    repeat (5) @(cfg.axi_vif.mon_cb);
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server server;
    super.report_phase(phase);
    server = uvm_report_server::get_server();
    if (server.get_severity_count(UVM_ERROR) == 0 &&
        server.get_severity_count(UVM_FATAL) == 0 &&
        env.scb.responses_checked > 0)
      `uvm_info("BRIDGE_TEST_PASS", $sformatf("%s completed with %0d checked responses", get_type_name(), env.scb.responses_checked), UVM_NONE)
  endfunction
endclass

class bridge_smoke_test extends bridge_base_test;
  `uvm_component_utils(bridge_smoke_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

class bridge_stress_test extends bridge_base_test;
  `uvm_component_utils(bridge_stress_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure();
    cfg.apb_min_wait = 0;
    cfg.apb_max_wait = 12;
    cfg.enable_error = 1;
  endfunction

  virtual task execute();
    bridge_smoke_sequence smoke;
    bridge_error_sequence errors;
    bridge_random_sequence random_seq;
    smoke = bridge_smoke_sequence::type_id::create("smoke");
    errors = bridge_error_sequence::type_id::create("errors");
    random_seq = bridge_random_sequence::type_id::create("random_seq");
    random_seq.iterations = cfg.num_random;
    smoke.start(env.axi.seqr);
    errors.start(env.axi.seqr);
    random_seq.start(env.axi.seqr);
  endtask
endclass

class bridge_reset_test extends bridge_base_test;
  `uvm_component_utils(bridge_reset_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task reset_during_wait(bridge_single_sequence seq);
    bit found_access;
    found_access = 0;
    fork
      seq.start(env.axi.seqr);
      begin
        for (int cycle = 0; cycle < cfg.timeout_cycles; cycle++) begin
          @(cfg.apb_vif.mon_cb);
          if (cfg.apb_vif.mon_cb.psel != 3'b000 &&
              cfg.apb_vif.mon_cb.penable === 1'b1) begin
            found_access = 1;
            break;
          end
        end
        if (!found_access)
          `uvm_fatal("RESET_SETUP", "No APB ACCESS observed before reset timeout")
        // Forty configured wait cycles guarantee this access is still pending.
        cfg.axi_vif.apply_reset(5);
      end
    join
    if (!seq.last_aborted)
      `uvm_error("RESET_ABORT", "The in-flight AXI item was not marked aborted by reset")
  endtask

  virtual task execute();
    bridge_smoke_sequence before_reset, recovery;
    bridge_single_sequence aborted_write, aborted_read, cleared_read;
    before_reset = bridge_smoke_sequence::type_id::create("before_reset");
    recovery = bridge_smoke_sequence::type_id::create("recovery");
    aborted_write = bridge_single_sequence::type_id::create("aborted_write");
    aborted_read = bridge_single_sequence::type_id::create("aborted_read");
    cleared_read = bridge_single_sequence::type_id::create("cleared_read");

    before_reset.start(env.axi.seqr);
    // Exercise idle reset after nonzero model contents, then read a previously
    // written address to prove both responder and reference memory were reset.
    cfg.axi_vif.apply_reset(4);
    cleared_read.write_access = 0;
    cleared_read.start(env.axi.seqr);

    cfg.apb_min_wait = 40;
    cfg.apb_max_wait = 40;
    aborted_write.permit_abort = 1;
    aborted_write.address = 32'h4000_2002; // GPIO
    aborted_write.write_data = 32'hDEAD_0000;
    aborted_write.write_strobes = 4'b1100;
    reset_during_wait(aborted_write);

    aborted_read.permit_abort = 1;
    aborted_read.write_access = 0;
    aborted_read.address = 32'h4000_3000; // TIMER
    reset_during_wait(aborted_read);

    cfg.apb_min_wait = 0;
    cfg.apb_max_wait = 5;
    cleared_read.address = 32'h4000_2002;
    cleared_read.start(env.axi.seqr);
    recovery.start(env.axi.seqr);
    if (env.scb.aborted_requests < 2)
      `uvm_error("RESET_COVERAGE", "Scoreboard did not observe both reset-aborted requests")
  endtask
endclass

// Negative regression: original RTL retains write PSTRB on a following read.
// This must report APB_READ_STRB; an error-free run is not the expected outcome.
class bridge_strict_apb_test extends bridge_base_test;
  `uvm_component_utils(bridge_strict_apb_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void configure();
    cfg.strict_apb = 1;
  endfunction
endclass

// Unmapped decode codes must complete with SLVERR and no APB transfer. The
// wrapper's response mux supplies a default error sink (APB_v1_0.v, else
// branch) and bridge_scoreboard predicts the SLVERR through rejected_request,
// so the response value is checked automatically; this test only confirms
// that both directions completed as rejections and that the bridge is still
// usable afterwards. Codes 0 and 4 are both unmapped (only 1/2/3 decode).
class bridge_unmapped_test extends bridge_base_test;
  `uvm_component_utils(bridge_unmapped_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual task execute();
    bridge_single_sequence unmapped_read, unmapped_write, mapped_read;
    unmapped_read = bridge_single_sequence::type_id::create("unmapped_read");
    unmapped_read.write_access = 0;
    unmapped_read.address = 32'h4000_0000;
    unmapped_read.start(env.axi.seqr);

    unmapped_write = bridge_single_sequence::type_id::create("unmapped_write");
    unmapped_write.address = 32'h4000_4000;
    unmapped_write.start(env.axi.seqr);

    mapped_read = bridge_single_sequence::type_id::create("mapped_read");
    mapped_read.write_access = 0;
    mapped_read.address = 32'h4000_1000;
    mapped_read.start(env.axi.seqr);

    if (env.scb.rejected_responses != 2)
      `uvm_error("UNMAPPED_RESP", $sformatf("Expected 2 SLVERR completions for unmapped addresses, scoreboard counted %0d", env.scb.rejected_responses))
    if (env.scb.apb_checked != 1)
      `uvm_error("UNMAPPED_APB", $sformatf("Only the mapped read may reach APB, scoreboard checked %0d transfers", env.scb.apb_checked))
  endtask
endclass

// Directed corners that the other tests never reach:
//  1. APB transfers that complete after 16..20 wait cycles (apb_coverage
//     cp_wait.extended_wait for read and write).
//  2. Reset while the core is in SETUP (PSTATE 1->0 FSM transition).
//  3. Reset after the APB transfer finished while B/R is held off by a low
//     BREADY/RREADY (bridge_coverage abort_cg.pending_response, read and write).
class bridge_corner_test extends bridge_base_test;
  `uvm_component_utils(bridge_corner_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task long_wait_access(bit is_write, bit [31:0] address);
    bridge_single_sequence seq;
    seq = bridge_single_sequence::type_id::create("long_wait");
    seq.write_access = is_write;
    seq.address = address;
    seq.start(env.axi.seqr);
  endtask

  // PSEL rises right after the clock edge that enters SETUP. apply_reset drops
  // resetn on the following falling edge, so the next rising edge resets the
  // core while PSTATE is still SETUP.
  task reset_in_setup(bit is_write, bit [31:0] address);
    bridge_single_sequence seq;
    seq = bridge_single_sequence::type_id::create("setup_abort");
    seq.permit_abort = 1;
    seq.write_access = is_write;
    seq.address = address;
    fork
      seq.start(env.axi.seqr);
      begin
        wait (cfg.apb_vif.psel !== 3'b000);
        if (cfg.apb_vif.penable !== 1'b0)
          `uvm_fatal("CORNER_SETUP", "PSEL rose outside SETUP")
        cfg.axi_vif.apply_reset(4);
      end
    join
    if (!seq.last_aborted)
      `uvm_error("CORNER_SETUP", "Reset during SETUP did not abort the AXI item")
  endtask

  // The response stall is far longer than the reset delay, so the reset
  // always lands while BVALID/RVALID is high and BREADY/RREADY is low.
  task reset_in_response(bit is_write, bit [31:0] address);
    bridge_single_sequence seq;
    seq = bridge_single_sequence::type_id::create("response_abort");
    seq.permit_abort = 1;
    seq.write_access = is_write;
    seq.address = address;
    seq.response_stall = 30;
    fork
      seq.start(env.axi.seqr);
      begin
        if (is_write) wait (cfg.axi_vif.bvalid === 1'b1);
        else wait (cfg.axi_vif.rvalid === 1'b1);
        repeat (2) @(posedge cfg.axi_vif.clk);
        cfg.axi_vif.apply_reset(4);
      end
    join
    if (!seq.last_aborted)
      `uvm_error("CORNER_RESPONSE", "Reset during the response stall did not abort the AXI item")
  endtask

  virtual task execute();
    bridge_smoke_sequence recovery;
    int unsigned aborted_before;

    cfg.apb_min_wait = 16;
    cfg.apb_max_wait = 20;
    long_wait_access(1, 32'h4000_1000);
    long_wait_access(0, 32'h4000_1000);
    cfg.apb_min_wait = 0;
    cfg.apb_max_wait = 5;

    aborted_before = env.scb.aborted_requests;
    reset_in_setup(0, 32'h4000_2000);
    // Lower halfword: the default strobes 0011 must not be a lane reject,
    // or the write would never reach APB.
    reset_in_response(1, 32'h4000_3000);
    reset_in_response(0, 32'h4000_3000);
    if (env.scb.aborted_requests - aborted_before != 3)
      `uvm_error("CORNER_ABORTS", $sformatf("Expected 3 reset-aborted requests, scoreboard counted %0d", env.scb.aborted_requests - aborted_before))

    recovery = bridge_smoke_sequence::type_id::create("recovery");
    recovery.start(env.axi.seqr);
  endtask
endclass

// Toggle-coverage test: runs bridge_toggle_sequence with APB errors enabled
// so PSLVERR_* and the SLVERR response paths toggle as well. Include it in
// make regress so its edges merge with bridge_reset_test, which supplies the
// 1->0 edge of s00_axi_aresetn that this test alone cannot produce.
class bridge_toggle_test extends bridge_base_test;
  `uvm_component_utils(bridge_toggle_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure();
    cfg.apb_min_wait = 0;
    cfg.apb_max_wait = 3;
    cfg.enable_error = 1;
  endfunction

  virtual task execute();
    bridge_toggle_sequence sweep;
    sweep = bridge_toggle_sequence::type_id::create("sweep");
    sweep.start(env.axi.seqr);
  endtask
endclass

// Read/write overlap regression (B01). axi_driver runs the write and read
// channels on separate engines, so forking one write and one read sequence
// puts AW/W and AR on the bus together. Each sweep shifts one direction by
// 0..N cycles against the other and reaches:
//  - simultaneous AW/W/AR (read wins the grant),
//  - the B01 boundary: ARVALID rising after AWREADY/WREADY were granted,
//  - a request arriving while the other direction's APB transfer is busy,
//  - a request arriving while the other direction's B/R response is stalled.
// The DUT accepts one transaction at a time, so handshake, APB and response
// order agree and bridge_scoreboard checks every pair unchanged. A stolen
// PADDR fails as APB_ADDR, a lost read as UNMATCHED/REQUEST_ACCOUNTING.
class bridge_overlap_test extends bridge_base_test;
  `uvm_component_utils(bridge_overlap_test)
  localparam bit [31:0] UART_ADDR = 32'h4000_1020;
  localparam bit [31:0] GPIO_ADDR = 32'h4000_2040;
  int unsigned expected_responses;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure();
    cfg.apb_min_wait = 2;
    cfg.apb_max_wait = 2;
  endfunction

  function bit [31:0] lane_word(bit [31:0] address, bit [15:0] halfword);
    return address[1] ? {halfword, 16'h0000} : {16'h0000, halfword};
  endfunction

  function bit [3:0] lane_strobes(bit [31:0] address);
    return address[1] ? 4'b1100 : 4'b0011;
  endfunction

  task single_write(bit [31:0] address, bit [15:0] halfword);
    bridge_single_sequence seq;
    seq = bridge_single_sequence::type_id::create("seed_write");
    seq.address = address;
    seq.write_data = lane_word(address, halfword);
    seq.write_strobes = lane_strobes(address);
    seq.start(env.axi.seqr);
    expected_responses++;
  endtask

  // aw_skew/w_skew delay the write, ar_skew the read; b_stall/r_stall hold
  // BREADY/RREADY low after BVALID/RVALID rises.
  task overlap_pair(bit [31:0] write_address, bit [31:0] read_address,
                    bit [15:0] halfword,
                    int unsigned aw_skew, int unsigned w_skew,
                    int unsigned ar_skew,
                    int unsigned b_stall = 0, int unsigned r_stall = 0);
    bridge_single_sequence wr, rd;
    wr = bridge_single_sequence::type_id::create("overlap_write");
    wr.address = write_address;
    wr.write_data = lane_word(write_address, halfword);
    wr.write_strobes = lane_strobes(write_address);
    wr.aw_skew = aw_skew;
    wr.w_skew = w_skew;
    wr.response_stall = b_stall;
    rd = bridge_single_sequence::type_id::create("overlap_read");
    rd.write_access = 0;
    rd.address = read_address;
    rd.ar_skew = ar_skew;
    rd.response_stall = r_stall;
    fork
      wr.start(env.axi.seqr);
      rd.start(env.axi.seqr);
    join
    expected_responses += 2;
  endtask

  // Mapped slave, random lane; occasionally the APB error address (bit 8)
  // or an odd address, which the bridge rejects with SLVERR.
  function bit [31:0] random_address();
    bit [31:0] address;
    address = 32'h4000_0000;
    address[14:12] = $urandom_range(3, 1);
    address[8] = ($urandom_range(3, 0) == 0);
    address[4:1] = $urandom_range(15, 0);
    address[0] = ($urandom_range(7, 0) == 0);
    return address;
  endfunction

  virtual task execute();
    int unsigned checked_before;
    checked_before = env.scb.responses_checked;
    expected_responses = 0;

    // Known contents, as in the B01 reproduction (UART=1234, GPIO=5678).
    single_write(UART_ADDR, 16'h1234);
    single_write(GPIO_ADDR, 16'h5678);

    // 1. Write first, read shifted 0..12 cycles. ar_skew 1 is the B01 boundary.
    for (int s = 0; s <= 12; s++)
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hBE00 + s, 0, 0, s);
    // 2. Read first, write shifted 0..12 cycles.
    for (int s = 0; s <= 12; s++)
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hC000 + s, s, s, 0);
    // 3. AW and W apart: the write is granted only once both are valid.
    for (int s = 0; s <= 6; s++) begin
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hD000 + s, 2, 0, s);
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hD100 + s, 0, 2, s);
    end
    // 4. BREADY held low: the read must wait for the B handshake.
    for (int s = 0; s <= 14; s++)
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hE000 + s, 0, 0, s, 8, 0);
    // 5. RREADY held low: the write must wait for the R handshake.
    for (int s = 0; s <= 14; s++)
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hE100 + s, s, s, 0, 0, 8);
    // 6. Same address both ways: read data follows the accepted order.
    for (int s = 0; s <= 6; s++) begin
      overlap_pair(UART_ADDR, UART_ADDR, 16'hF000 + s, 0, 0, s);
      overlap_pair(UART_ADDR, UART_ADDR, 16'hF100 + s, s, s, 0);
    end
    // 7. Long APB wait: the other direction arrives during the transfer.
    cfg.apb_min_wait = 8;
    cfg.apb_max_wait = 8;
    for (int s = 0; s <= 14; s += 2) begin
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hA000 + s, 0, 0, s);
      overlap_pair(UART_ADDR, GPIO_ADDR, 16'hA100 + s, s, s, 0);
    end

    // 8. Random mix with APB errors, rejects, waits and stalls.
    cfg.apb_min_wait = 0;
    cfg.apb_max_wait = 5;
    cfg.enable_error = 1;
    for (int i = 0; i < cfg.num_random; i++)
      overlap_pair(random_address(), random_address(), $urandom,
                   $urandom_range(6, 0), $urandom_range(6, 0),
                   $urandom_range(10, 0),
                   $urandom_range(6, 0), $urandom_range(6, 0));
    cfg.enable_error = 0;

    // Every accepted request must produce exactly one checked response.
    if (env.scb.responses_checked - checked_before != expected_responses)
      `uvm_error("OVERLAP_RESPONSES", $sformatf("Expected %0d checked responses, scoreboard checked %0d", expected_responses, env.scb.responses_checked - checked_before))
  endtask
endclass

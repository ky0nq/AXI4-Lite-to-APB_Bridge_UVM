class bridge_sequence_base extends uvm_sequence #(axi_item);
  `uvm_object_utils(bridge_sequence_base)
  bit permit_abort = 0;
  bit last_aborted = 0;

  function new(string name = "bridge_sequence_base");
    super.new(name);
  endfunction

  function bit [31:0] slave_base(int slave);
    case (slave)
      0: return 32'h4000_1000; // UART
      1: return 32'h4000_2000; // GPIO
      2: return 32'h4000_3000; // TIMER
      default: begin
        `uvm_fatal("SLAVE_INDEX", $sformatf("slave_base: index %0d is not 0..2", slave))
        return 32'h0000_0000;
      end
    endcase
  endfunction

  function bit [31:0] lane_data(bit [15:0] halfword, bit upper);
    return upper ? {halfword, 16'h0000} : {16'h0000, halfword};
  endfunction

  function bit [3:0] lane_strobes(bit [1:0] strobes, bit upper);
    return upper ? {strobes, 2'b00} : {2'b00, strobes};
  endfunction

  // axi_driver calls item_done when an engine takes the item, before the
  // response. Waiting for done keeps one outstanding item per sequence.
  task finish_and_wait(axi_item req);
    finish_item(req);
    wait (req.done);
  endtask

  task send_access(bit is_write, bit [31:0] address,
                   bit [31:0] data_word = 0, bit [3:0] strobes = 0,
                   int unsigned aw_skew = 0, int unsigned w_skew = 0,
                   int unsigned ar_skew = 0, int unsigned response_stall = 0,
                   bit [2:0] protection = 0);
    axi_item req;
    req = axi_item::type_id::create("req");
    start_item(req);
    req.write = is_write;
    req.addr = address;
    req.data = data_word;
    req.strb = strobes;
    req.prot = protection;
    req.aw_delay = aw_skew;
    req.w_delay = w_skew;
    req.ar_delay = ar_skew;
    req.response_delay = response_stall;
    finish_and_wait(req);
    last_aborted = req.aborted;
    if (req.aborted && !permit_abort)
      `uvm_error("UNEXPECTED_ABORT", $sformatf("Unexpected reset aborted addr=%08h", address))
  endtask
endclass

// Every mapped slave, both halfword lanes, all four selected-halfword byte
// strobes, AW-before-W/W-before-AW/simultaneous, and response backpressure.
class bridge_smoke_sequence extends bridge_sequence_base;
  `uvm_object_utils(bridge_smoke_sequence)
  function new(string name = "bridge_smoke_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] address;
    for (int slave = 0; slave < 3; slave++) begin
      for (int lane = 0; lane < 2; lane++) begin
        address = slave_base(slave) + lane * 2;
        send_access(0, address, 0, 0, 0, 0, 1, 2, 3'b101);
        send_access(1, address, lane_data(16'hA1B2 + slave, lane != 0), lane_strobes(2'b11, lane != 0), 0, 0, 0, 0, 3'b111);
        send_access(0, address, 0, 0, 0, 0, 0, 4);
        send_access(1, address, lane_data(16'hC3D4, lane != 0), lane_strobes(2'b01, lane != 0), 0, 5, 0, 3, 3'b001);
        send_access(0, address, 0, 0, 0, 0, 2, 0);
        send_access(1, address, lane_data(16'hE5F6, lane != 0), lane_strobes(2'b10, lane != 0), 6, 0, 0, 5, 3'b010);
        send_access(0, address, 0, 0, 0, 0, 0, 6);
        send_access(1, address, lane_data(16'hFFFF, lane != 0), lane_strobes(2'b00, lane != 0), 2, 2, 0, 2);
        send_access(0, address);
      end
    end
  endtask
endclass

// Seed error addresses while errors are disabled, attempt rejected writes,
// and check both error-read data and subsequent successful readback. The
// scoreboard independently predicts the unchanged memory in all three cases.
class bridge_error_sequence extends bridge_sequence_base;
  `uvm_object_utils(bridge_error_sequence)
  bridge_cfg cfg;
  function new(string name = "bridge_error_sequence");
    super.new(name);
  endfunction

  task body();
    bit [31:0] address;
    if (!uvm_config_db#(bridge_cfg)::get(m_sequencer, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "bridge_error_sequence requires bridge_cfg")
    for (int slave = 0; slave < 3; slave++) begin
      for (int lane = 0; lane < 2; lane++) begin
        address = slave_base(slave) + 32'h100 + lane * 2;
        cfg.enable_error = 0;
        send_access(1, address, lane_data(16'h596A + slave, lane != 0), lane_strobes(2'b11, lane != 0), 0, 4, 0, 3);
        cfg.enable_error = 1;
        send_access(1, address, lane_data(16'hFFFF, lane != 0), lane_strobes(2'b11, lane != 0), 4, 0, 0, 7);
        send_access(0, address, 0, 0, 0, 0, 3, 8);
        cfg.enable_error = 0;
        send_access(0, address);
      end
    end
    cfg.enable_error = 1;
  endtask
endclass

class bridge_random_sequence extends bridge_sequence_base;
  `uvm_object_utils(bridge_random_sequence)
  int unsigned iterations = 100;
  function new(string name = "bridge_random_sequence");
    super.new(name);
  endfunction

  task body();
    axi_item req;
    for (int i = 0; i < iterations; i++) begin
      req = axi_item::type_id::create($sformatf("random_req_%0d", i));
      start_item(req);
      // Keep the working set small enough to revisit partial writes. Address
      // bit 8 still alternates between successful and failing APB accesses.
      if (!req.randomize() with { addr[7:5] == 3'b000; })
        `uvm_fatal("RANDOMIZE", "AXI request constraints are unsatisfiable")
      finish_and_wait(req);
      if (req.aborted)
        `uvm_error("UNEXPECTED_ABORT", "Random request was reset-aborted")
      if (req.write)
        send_access(0, req.addr, 0, 0, 0, 0, $urandom_range(6, 0), $urandom_range(10, 0), req.prot);
    end
  endtask
endclass

class bridge_single_sequence extends bridge_sequence_base;
  `uvm_object_utils(bridge_single_sequence)
  bit write_access = 1;
  bit [31:0] address = 32'h4000_1000;
  bit [31:0] write_data = 32'h0000_CAFE;
  bit [3:0] write_strobes = 4'b0011;
  // Cycles BREADY/RREADY stay low after BVALID/RVALID rises.
  int unsigned response_stall = 0;
  // Cycles before AWVALID/WVALID/ARVALID rise, counted from when the driver
  // takes the item. bridge_overlap_test uses them to skew two directions.
  int unsigned aw_skew = 0;
  int unsigned w_skew = 0;
  int unsigned ar_skew = 0;
  function new(string name = "bridge_single_sequence");
    super.new(name);
  endfunction
  task body();
    send_access(write_access, address, write_data, write_strobes,
                aw_skew, w_skew, ar_skew, response_stall);
  endtask
endclass

// Toggle-coverage sweep for VCS -cm tgl. Structural toggle coverage needs
// every DUT bit to see a 0->1 and a 1->0 edge. The smoke and random stimulus
// keep addresses inside the register map, so PADDR/AWADDR/ARADDR bits 31:15,
// 11:9 and 0 never move. This sequence walks a single 1 through every AXI
// address, data, strobe and protection bit: bit 0 reaches the odd-address
// reject, the unmapped codes 0/4/5/6/7 reach the wrapper's default SLVERR
// sink, and the remaining address bits prove PADDR
// forwards all 32 bits. The scoreboard predicts every one of these cases, so
// an error-free run is still the expected outcome.
class bridge_toggle_sequence extends bridge_sequence_base;
  `uvm_object_utils(bridge_toggle_sequence)
  // Decode codes the register map never produces (1/2/3 are UART/GPIO/TIMER).
  bit [2:0] unmapped_codes[5] = '{3'd0, 3'd4, 3'd5, 3'd6, 3'd7};

  function new(string name = "bridge_toggle_sequence");
    super.new(name);
  endfunction

  // Write a halfword into the lane selected by address[1], then read it back
  // so WDATA, PWDATA, PRDATA_* and RDATA all carry the pattern.
  task write_read(bit [31:0] address, bit [15:0] halfword);
    send_access(1, address, lane_data(halfword, address[1]),
                lane_strobes(2'b11, address[1]));
    send_access(0, address);
  endtask

  task body();
    bit [31:0] base;
    bit [31:0] address;

    // 1. Data path: all-ones, all-zeros and a walking 1 through both lanes of
    //    every slave, so each PRDATA_* input and both RDATA halves toggle.
    for (int slave = 0; slave < 3; slave++) begin
      for (int lane = 0; lane < 2; lane++) begin
        address = slave_base(slave) + lane * 2;
        write_read(address, 16'hFFFF);
        write_read(address, 16'h0000);
        for (int bit_pos = 0; bit_pos < 16; bit_pos++)
          write_read(address, 16'h0001 << bit_pos);
        write_read(address, 16'h0000);
      end
    end

    // 2. Strobes: each byte enable of each lane, then strobes in the wrong
    //    lane and in both lanes, which the bridge must reject with SLVERR
    //    and no APB transfer (write_reject toggles both ways).
    for (int lane = 0; lane < 2; lane++) begin
      address = slave_base(0) + lane * 2;
      send_access(1, address, lane_data(16'h00FF, lane != 0), lane_strobes(2'b01, lane != 0));
      send_access(1, address, lane_data(16'hFF00, lane != 0), lane_strobes(2'b10, lane != 0));
      send_access(1, address, lane_data(16'hFFFF, lane != 0), lane_strobes(2'b11, lane != 0));
      send_access(1, address, 32'hFFFF_FFFF, lane_strobes(2'b11, lane == 0));
      send_access(1, address, 32'hFFFF_FFFF, 4'b1111);
      send_access(0, address);
    end

    // 3. Protection: every AxPROT value on both channels (PPROT / apb_prot).
    address = slave_base(1);
    for (int prot = 0; prot < 8; prot++) begin
      send_access(1, address, lane_data(16'h0A50 | prot[2:0], 0), lane_strobes(2'b11, 0),
                  0, 0, 0, 0, prot[2:0]);
      send_access(0, address, 0, 0, 0, 0, 0, 0, prot[2:0]);
    end

    // 4. Address walk: flip one bit of the UART base per write/read pair.
    //    The next pair restores the previous bit, so every AWADDR, ARADDR,
    //    axi_awaddr/axi_araddr and PADDR bit sees both edges. Bit 0 is the
    //    reject path, bit 8 the APB error address, bits 12..14 reach the
    //    unmapped codes 0 and 5 and the TIMER code 3, bit 30 leaves the
    //    0x4000 region.
    base = slave_base(0);
    for (int bit_pos = 0; bit_pos < 32; bit_pos++) begin
      address = base ^ (32'h0000_0001 << bit_pos);
      send_access(1, address, lane_data(16'h5A5A, address[1]), lane_strobes(2'b11, address[1]));
      send_access(0, address);
    end
    write_read(base, 16'h0000);

    // 5. Unmapped decodes: no PSEL_* rises and the wrapper's default sink
    //    completes each access with SLVERR.
    foreach (unmapped_codes[i]) begin
      address = {16'h4000, 1'b0, unmapped_codes[i], 12'h000};
      write_read(address, 16'hA5A5);
    end
  endtask
endclass

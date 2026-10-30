class apb_responder extends uvm_component;
  `uvm_component_utils(apb_responder)

  bridge_cfg cfg;
  virtual apb_if vif;
  bit [15:0] memory[bit [31:0]];
  bit active;
  int selected;
  int unsigned waits_left;
  bit [31:0] address_key;
  bit [15:0] write_data, read_data;
  bit [1:0] write_strobes;
  bit write_transfer, transfer_error;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bridge_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "apb_responder requires bridge_cfg")
    vif = cfg.apb_vif;
    if (vif == null)
      `uvm_fatal("NO_VIF", "apb_responder requires apb_vif")
    if (cfg.apb_min_wait > cfg.apb_max_wait)
      `uvm_fatal("WAIT_CFG", "apb_min_wait must not exceed apb_max_wait")
  endfunction

  // Inactive slaves deliberately disagree with the selected slave. This
  // exposes an incorrect PRDATA/PREADY/PSLVERR mux in the DUT wrapper.
  function void drive_poison();
    vif.pready      = 3'b111;
    vif.pslverr     = 3'b111;
    vif.prdata_uart = 16'hd011;
    vif.prdata_gpio = 16'hd033;
    vif.prdata_timer= 16'hd055;
  endfunction

  function void drive_reset();
    vif.pready       = '0;
    vif.pslverr      = '0;
    vif.prdata_uart  = '0;
    vif.prdata_gpio  = '0;
    vif.prdata_timer = '0;
  endfunction

  task run_phase(uvm_phase phase);
    active = 0;
    drive_reset();
    fork
      begin : drive_responses
        forever begin
          @(negedge vif.clk);
          if (vif.resetn !== 1'b1) begin
            drive_reset();
          end else begin
            drive_poison();
            if (!active && vif.penable === 1'b0) begin
              case (vif.psel)
                3'b001: selected = 0;
                3'b010: selected = 1;
                3'b100: selected = 2;
                default: selected = -1;
              endcase
              if (selected >= 0) begin
                active = 1;
                address_key = {vif.paddr[31:1], 1'b0};
                write_transfer = vif.pwrite;
                write_data = vif.pwdata;
                write_strobes = vif.pstrb;
                waits_left = $urandom_range(cfg.apb_max_wait,
                                           cfg.apb_min_wait);
                transfer_error = cfg.enable_error &&
                    ((vif.paddr & cfg.error_mask) == cfg.error_match);
                read_data = memory.exists(address_key) ?
                            memory[address_key] : 16'h0000;
              end
            end
            if (active) begin
              vif.pready[selected] = (waits_left == 0);
              vif.pslverr[selected] = transfer_error;
              case (selected)
                0: vif.prdata_uart  = read_data;
                1: vif.prdata_gpio  = read_data;
                2: vif.prdata_timer = read_data;
              endcase
            end
          end
        end
      end
      begin : observe_completions
        forever begin
          @(vif.mon_cb);
          if (vif.mon_cb.resetn !== 1'b1) begin
            active = 0;
            memory.delete();
          end else if (active && vif.mon_cb.penable === 1'b1 &&
                       vif.mon_cb.psel[selected] === 1'b1) begin
            if (vif.mon_cb.pready[selected] === 1'b1) begin
              if (write_transfer && !transfer_error) begin
                if (!memory.exists(address_key)) memory[address_key] = '0;
                if (write_strobes[0])
                  memory[address_key][7:0] = write_data[7:0];
                if (write_strobes[1])
                  memory[address_key][15:8] = write_data[15:8];
              end
              active = 0;
            end else if (vif.mon_cb.pready[selected] === 1'b0 &&
                         waits_left != 0) begin
              waits_left--;
            end
          end
        end
      end
      begin : reset_memory
        forever begin
          @(negedge vif.resetn);
          active = 0;
          memory.delete();
        end
      end
    join
  endtask
endclass


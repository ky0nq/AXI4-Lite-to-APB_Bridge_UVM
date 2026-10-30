`timescale 1ns/1ps

interface apb_if(input logic clk, input logic resetn);
  logic [31:0] paddr;
  // Vector bit 0 = UART, bit 1 = GPIO, bit 2 = TIMER.
  logic [2:0] psel, pready, pslverr, pprot;
  logic penable, pwrite;
  logic [15:0] pwdata, prdata_uart, prdata_gpio, prdata_timer;
  logic [1:0] pstrb;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input resetn, paddr, psel, penable, pwrite, pwdata, pstrb, pprot;
    input pready, pslverr, prdata_uart, prdata_gpio, prdata_timer;
  endclocking
endinterface

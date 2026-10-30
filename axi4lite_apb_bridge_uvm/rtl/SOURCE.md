# Upstream DUT

Repository: https://github.com/ky0nq/V-TRAX-Vision-AI-SoC

Pinned commit: `4bbf2ad5afe18cf3e062d60ad5c561f518d835a5`

Both Verilog files are copied from `Zybo_IP/IP_AXI_APB/src/` without logic changes:

- `APB_v1_0.v`: top-level mux and UART/GPIO/TIMER ports.
- `APB_v1_0_S00_AXI.v`: AXI4-Lite slave and APB state machine.

The downloaded bytes were checked against the upstream Git blob IDs:

| File | Git blob SHA-1 |
|---|---|
| APB_v1_0.v | f6cf95fc1b1128ba3dc96338f616883c66d51be0 |
| APB_v1_0_S00_AXI.v | 8d3932a52e96f398581926c77387cfa3600de67b |

The verification top instantiates `APB_v1_0` with AXI data/address widths 32 and APB data width 16. These are the widths actually implemented by the hard-coded halfword lane logic. The testbench does not claim arbitrary parameter support.

The upstream module exposes only UART/GPIO/TIMER. SCCB and AI decode signals exist inside the core but have no connected response path in the wrapper.

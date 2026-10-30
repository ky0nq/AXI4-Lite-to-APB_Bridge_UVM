# Upstream DUT

Repository: https://github.com/ky0nq/V-TRAX-Vision-AI-SoC

Pinned commit: `4bbf2ad5afe18cf3e062d60ad5c561f518d835a5`

Both Verilog files started from `Zybo_IP/IP_AXI_APB/src/` at the pinned commit.
The files in this directory are the **fixed versions** used for UVM verification, not byte-identical copies:

- `APB_v1_0.v`: top-level mux and UART/GPIO/TIMER ports, plus a default error sink for unmapped addresses.
- `APB_v1_0_S00_AXI.v`: AXI4-Lite slave and APB state machine, with the arbitration and protocol fixes below.

| File | Upstream blob SHA-1 (original) | This repository (fixed) |
|---|---|---|
| APB_v1_0.v | f6cf95fc1b1128ba3dc96338f616883c66d51be0 | 6d7010f6cd438d4b896ddbb683d92747ff8bacc8 |
| APB_v1_0_S00_AXI.v | 8d3932a52e96f398581926c77387cfa3600de67b | ff3057eda3a2e4d382a6f00543af1f19d8a41e44 |

## Changes from upstream

| ID | Change |
|---|---|
| B01 | One arbiter (`write_grant` / `read_grant`) reserves a transaction from READY issue until the B/R response is consumed, so a read can no longer overwrite `PADDR` of an accepted write. |
| B02 | Reads drive `PSTRB = 0`. |
| B03 | Unmapped decode codes (`PADDR[14:12]` = 0, 4–7) complete with SLVERR from the wrapper default sink instead of waiting forever. |
| B04 | Supported scope fixed as a 16-bit halfword register bridge: odd addresses and strobes outside the selected halfword return SLVERR without an APB transfer. It is not a two-transfer 32→16 width converter. |
| B05 | Accepted `AxPROT` is held and driven on `PPROT` through the APB transfer. |
| B06 | Declaration order cleaned up so the files compile without ordering errors. |
| Address map | Decode codes renumbered and unused slaves removed. Upstream: UART 1, SCCB 2, GPIO 3, AI 4, TIMER 5. This repository: UART 1, GPIO 2, TIMER 3; SCCB and AI ports were removed (they had no response path in the upstream wrapper). The fixed RTL is therefore **not a drop-in replacement** for firmware that uses the upstream GPIO / TIMER addresses. |

See the top-level [README](../../README.md) for how each item was reproduced and verified.

## Parameters

The verification top instantiates `APB_v1_0` with AXI data/address widths 32 and APB data width 16.
These are the widths actually implemented by the hard-coded halfword lane logic. The testbench does not claim arbitrary parameter support.

# AXI4-Lite → APB Bridge : RTL 결함 분석 및 UVM 검증

V-TRAX Vision AI SoC에서 사용한 **AXI4-Lite → APB Bridge IP**의 결함을 분석해 수정하고,
UVM 환경에서 regression과 Code/Functional Coverage closure까지 수행한 개인 프로젝트입니다.

| 항목 | 내용 |
|---|---|
| 기간 | 2026.10.16 – 2026.10.19 |
| 형태 | 개인 프로젝트 (기여도 100%) |
| DUT | AXI4-Lite 32-bit → APB 16-bit halfword bridge, UART · GPIO · TIMER slave |
| 언어 | SystemVerilog · Verilog |
| 검증 | UVM 1.1d · Scoreboard · Protocol Checker · Constrained Random · Code/Functional Coverage |
| 도구 | Synopsys VCS W-2024.09-SP2 · Verdi · urg |
| Upstream | [ky0nq/V-TRAX-Vision-AI-SoC](https://github.com/ky0nq/V-TRAX-Vision-AI-SoC) `Zybo_IP/IP_AXI_APB/src/` |

## 핵심 성과

- 원본 RTL 분석 항목 **6건(B01–B06)** 을 규격 기준으로 분류하고 수정 반영
- Regression test **8개 전체 PASS** · UVM_ERROR **0건** · AXI 요청 **1,245건** 검증
- Coverage SCORE **63.49 → 97.24** · TOGGLE · FSM · GROUP **100%**
- Read/Write overlap test **402건**에서 주소 변조 · read 유실 **0건** (B01 수정 검증)
- Multi-seed 회귀 (stress · overlap × seed 1–20) **40/40 PASS**

## DUT 동작

Bridge core는 AXI4-Lite 요청을 **한 번에 하나씩** APB SETUP → ACCESS로 변환하고,
wrapper가 `PADDR[14:12]`로 slave를 선택한 뒤 `PRDATA`/`PSLVERR`을 AXI R/B 응답으로 돌려줍니다.

| 항목 | AXI4-Lite | APB |
|---|---|---|
| Slave 선택 | 주소 bit 14:12 = 1 / 2 / 3 | `PSEL_UART` / `PSEL_GPIO` / `PSEL_TIMER`, 나머지 코드는 SLVERR |
| 데이터 | bit 1로 상·하위 halfword 선택 | `PWDATA[15:0]` · `PRDATA[15:0]` |
| Strobe | `WSTRB[1:0]` 또는 `WSTRB[3:2]` | `PSTRB[1:0]`, read 시 0 |
| 보호 속성 | `AWPROT` / `ARPROT` | `PPROT` 그대로 전달 |
| Reject | 홀수 주소, 반대 lane · 양 lane strobe | APB 전송 없이 즉시 SLVERR |
| 중재 | READY 발행 시점부터 응답 완료까지 슬롯 예약 | 동시 요청 시 read 우선 |

32-bit 요청을 APB 2회로 나누는 범용 width converter가 아니라, **16-bit halfword register 전용 bridge**로 지원 범위를 정했습니다.

> **주소 맵 변경** : upstream은 UART 1 · SCCB 2 · GPIO 3 · AI 4 · TIMER 5였고, SCCB · AI는 wrapper에 응답 경로가 없었습니다.
> 수정본은 미사용 slave를 제거하고 UART 1 · GPIO 2 · TIMER 3으로 정리했습니다.
> 따라서 upstream 주소를 쓰는 firmware에 그대로 넣으려면 주소 정의를 함께 바꿔야 합니다. 변경 내역은 [`rtl/SOURCE.md`](axi4lite_apb_bridge_uvm/rtl/SOURCE.md)에 있습니다.

## 원본 RTL 분석 항목 (B01–B06)

| ID | 분류 | 내용 | 처리 |
|---|---|---|---|
| B01 | 동작 결함 | Write 수락 직후 Read가 APB 주소를 덮어써 다른 slave에 쓰기 발생, 수락한 read 유실 | READY 발행 시점부터 슬롯을 예약하는 단일 arbiter (`write_grant` / `read_grant`) |
| B02 | 프로토콜 신호 | Read 전송에서 `PSTRB`가 남음 | Read 시 `PSTRB=0`, `bridge_strict_apb_test`로 회귀 |
| B03 | 오류 응답 | 미매핑 주소에서 응답 없이 대기 | Wrapper default sink가 SLVERR로 종료, `bridge_unmapped_test`로 회귀 |
| B04 | 지원 범위 | 32-bit → 16-bit 변환 정책 미정 | Halfword register 전용으로 지원 범위 확정 |
| B05 | 속성 전달 | AXI 보호 속성이 APB로 전달되지 않음 | `AxPROT` → `PPROT` 전달 |
| B06 | 빌드 | 선언 순서 오류 | 선언 순서 정리 |

6건은 같은 종류의 버그 6개가 아니라, 동작 결함 · 인터페이스 정책 · 빌드 문제를 구분해 기록한 것입니다.

### B01 상세

- **현상** : UART write(`0x40001020`, `0xBEEF`)의 AWREADY/WREADY 직후 GPIO read(`0x40003040`)의 ARVALID를 인가하면,
  APB SETUP은 UART 주소였지만 ACCESS에서 GPIO 주소로 바뀌어 GPIO에 `BEEF`가 기록되고 read 응답은 0회였습니다.
  AW/W/AR을 같은 시점에 올린 대조군은 정상이라, 동시 요청이 아니라 **수락 경계**의 문제로 범위를 좁혔습니다.
- **원인** : `ARREADY` 조건이 현재 APB busy(`PSTATE`)만 보고, 이미 발행된 write READY를 예약된 요청으로 세지 않았습니다.
- **해결** : "READY 발행 = 슬롯 점유"로 정의하고, 하나의 arbiter에서 양방향을 결정하도록 수정했습니다.
- **검증** : AXI driver를 write / read 채널 엔진으로 분리하고 `bridge_overlap_test`를 추가해,
  read를 0–14 cycle 늦추는 sweep과 random 조합 402건에서 `APB_ADDR` · `UNMATCHED` · `REQUEST_ACCOUNTING` 에러 0건을 확인했습니다.

## UVM 검증 환경

```
tb_top
 ├─ DUT : APB_v1_0 (wrapper) ─ APB_v1_0_S00_AXI (bridge core)
 ├─ bridge_protocol_checker      AXI/APB 안정성 · X · phase 규칙 상시 검사
 └─ uvm_test → bridge_env
     ├─ axi_agent   driver (write / read 채널 엔진 분리) · monitor (request / response port 2개)
     ├─ apb_agent   responder (slave 역할, wait · PSLVERR 주입) · monitor
     ├─ bridge_scoreboard   reference memory 기반 transaction 단위 예측 · 비교
     └─ coverage    apb_coverage · axi_coverage · bridge_coverage (covergroup 6개)
```

| Covergroup | 관측 대상 |
|---|---|
| `apb_coverage.transfer_cg` | slave × direction × lane × strobe × wait(0 / 1 / 2–3 / 4–15 / 16+) × error |
| `axi_coverage.response_cg` | 응답 종류, reject 원인(unmapped / misaligned / lane / pslverr), PROT 0–7 |
| `bridge_coverage.outcome_cg` | 방향 × 종료 경로 (APB OKAY / APB PSLVERR / reject) |
| `bridge_coverage.transition_cg` | 연속 transaction의 방향 쌍(R→R, R→W, W→R, W→W) · slave 쌍 |
| `bridge_coverage.read_history_cg` | read 데이터 출처 (초기값 / 정상 write 후 / error write 후) |
| `bridge_coverage.abort_cg` | 방향 × reset 시점 (APB 전송 전 / 응답 대기 중) |

Toggle coverage는 covergroup으로 다시 만들지 않고 VCS structural toggle(`-cm tgl`)로 수집했습니다.
측정 범위 · 자극 · 제외 근거는 [`cov/README.md`](axi4lite_apb_bridge_uvm/cov/README.md)에 정리했습니다.

## Regression

PASS 조건은 UVM_ERROR / UVM_FATAL 0건이고, 검사한 응답이 1개 이상인 경우입니다. (SEED=1)

| Test | 자극 · 목적 | AXI 요청 | 결과 |
|---|---|---:|---|
| `bridge_smoke_test` | 3 slave × 2 lane × 9 access, strobe · AW/W 순서 · PROT 기본 변환 | 54 | PASS |
| `bridge_stress_test` | APB wait 0–12, PSLVERR, random sequence, read-back | 229 | PASS |
| `bridge_reset_test` | idle reset, APB ACCESS 중 reset 후 복구 | 112 | PASS |
| `bridge_strict_apb_test` | read 시 `PSTRB=0` 등 APB4 엄격 규칙 (B02) | 54 | PASS |
| `bridge_unmapped_test` | 미매핑 read / write → APB 전송 없이 SLVERR (B03) | 3 | PASS |
| `bridge_toggle_test` | 데이터 walking-1 · strobe · PROT 0–7 · 주소 32-bit walk | 332 | PASS |
| `bridge_corner_test` | wait 16–20, SETUP 중 reset, B/R 응답 대기 중 reset | 59 | PASS |
| `bridge_overlap_test` | read/write 동시 요청 0–14 cycle skew sweep, B/R stall (B01) | 402 | PASS |

## Coverage closure

Regression을 4회차에 걸쳐 확장하며 coverage hole을 분석했습니다.

| 회차 | 실행 | SCORE | LINE | COND | TOGGLE | FSM | BRANCH | GROUP |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| ver1 | smoke 1개 | 63.49 | 91.96 | 76.00 | 55.50 | 75.00 | 86.00 | 59.93 |
| ver2 | regress 6개 | 78.43 | 98.21 | 84.00 | 100.00 | 75.00 | 98.00 | 93.78 |
| ver3 | regress 7개 | 96.70 | 98.21 | 84.00 | 100.00 | 100.00 | 98.00 | 100.00 |
| ver4 | regress 8개 | **97.24** | 98.21 | 87.20 | 100.00 | 100.00 | 98.00 | 100.00 |

남은 LINE · BRANCH · COND hole은 `modinfo.txt`와 RTL grant/READY 로직을 대조해 **모두 도달 불가**로 판정했고,
근거를 남긴 뒤 exclusion을 적용하면 LINE · BRANCH · COND도 100%입니다.
Exclusion은 자극으로 채울 수 없는 항목에만 사용했습니다.

> 저장소의 `coverage_report/`와 `regress.log`는 마지막으로 실행한 **multi-seed 회귀**
> (`bridge_stress_test` · `bridge_overlap_test` × seed 1–20) 결과입니다.
> 위 표의 ver4 수치는 8개 test 전체 regression 기준이므로, 재현하려면 아래처럼 `make regress` 후 `make report`를 실행하세요.

## 실행 방법

VCS / Verdi 환경이 설정된 Linux 서버에서 `axi4lite_apb_bridge_uvm/` 디렉터리 기준으로 실행합니다.

```bash
cd axi4lite_apb_bridge_uvm

make run                                   # 기본 bridge_smoke_test
make run TEST=bridge_overlap_test SEED=7   # test / seed 지정
make regress                               # 8개 test 전체
make report                                # coverage merge → coverage_report/dashboard.html
make regress_seeds SEEDS="1 7 42 100"      # 모든 test × seed
make wave TEST=bridge_reset_test           # wave.fsdb 덤프 후 Verdi
make help                                  # 전체 target
```

## 디렉터리 구조

```
axi4lite_apb_bridge_uvm/
├── rtl/
│   ├── APB_v1_0.v              wrapper : slave decode · 응답 mux · default sink (SLVERR)
│   └── APB_v1_0_S00_AXI.v      bridge core : arbiter · APB FSM (수정본)
├── tb/
│   ├── interfaces/             axi_lite_if.sv · apb_if.sv
│   ├── bridge_pkg.sv           UVM class include (class 파일은 따로 컴파일하지 않음)
│   ├── axi_* · apb_*           agent · driver · monitor · responder · item · coverage
│   ├── bridge_scoreboard.sv · bridge_protocol_checker.sv · bridge_coverage.sv
│   ├── bridge_sequence.sv · bridge_test.sv
│   └── tb_top.sv
├── cov/                        cm_hier.cfg (측정 범위) · bridge_toggle.el (exclusion) · README.md
├── coverage_report/            urg HTML / text 리포트
├── Makefile
└── *.log                       compile · regression · seed별 simulation 로그
```

## 배운 점

- **"수락"의 정의가 설계 안정성을 결정한다** : AXI READY/VALID 경계에서 READY 발행 시점부터 슬롯을 점유해야 APB 주소 안정성이 보장됩니다.
- **PASS는 TB가 만들 수 있는 자극 범위 안의 PASS** : 기존 test 7개가 모두 PASS였지만, driver가 read/write를 겹칠 수 없어 B01을 재현하지 못했습니다.
- **Exclusion은 근거가 있을 때만** : 시뮬레이터는 "안 나왔다"까지만 알려주므로, "절대 안 나온다"는 RTL 추론이나 formal로 증명해야 합니다.
- **Seed의 의미** : seed 고정은 재현성, seed 확장은 탐색 범위입니다.

## 개선 방향

- DUT에 SVA(APB 주소 안정성, read `PSTRB=0`, 수락 요청 1:1 응답)를 추가해 assertion coverage를 지표로 편입
- 도달 불가 판정을 formal 도구(VC Formal FCA 등)로 증명
- Read 우선 정책의 write starvation에 대한 공정성 검토

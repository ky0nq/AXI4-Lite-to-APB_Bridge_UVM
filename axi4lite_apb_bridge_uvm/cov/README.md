# AXI4-Lite → APB Bridge : Toggle Coverage 방침

## 결론

Toggle coverage 는 UVM 코드로 다시 만들지 않고 **VCS structural toggle (`-cm tgl`)** 로 수집한다.
UVM 쪽은 세 가지만 책임진다.

| 역할 | 파일 | 내용 |
|---|---|---|
| 범위 | `cov/cm_hier.cfg` | `+tree tb_top.dut` : DUT 두 모듈만 측정. interface / checker / UVM class 비트는 제외 |
| 자극 | `tb/bridge_sequence.sv` `bridge_toggle_sequence`, `tb/bridge_test.sv` `bridge_toggle_test` | 모든 AXI 주소·데이터·스트로브·PROT 비트를 양방향으로 흔드는 sweep |
| 제외 | `cov/bridge_toggle.el` | 설계상 토글이 불가능한 비트만 등록 (사유 주석 포함) |

`Makefile` 이 위 세 파일을 묶는다.
컴파일 `-cm line+cond+fsm+tgl+branch -cm_hier cov/cm_hier.cfg -cm_noconst -cm_seqnoconst`,
리포트 `urg ... -elfile cov/bridge_toggle.el`.

## 왜 covergroup 으로 안 하나

- Toggle 은 "RTL 의 모든 reg/wire 비트가 0→1, 1→0 을 봤는가" 라는 구조적 지표다. simulator 가 DUT 내부
  신호(`PSTATE`, `aw_en`, `write_reject`, 내부 `PSEL` …) 까지 자동으로 센다.
- covergroup 은 monitor 가 보는 bus 신호만 볼 수 있고, 비트 토글 bin 을 손으로 만들면 같은 정보를 두 번 세는 셈이다.
- 기존 `apb_coverage.transfer_cg` 는 functional coverage (slave × direction × lane × strobe × wait × error) 로 그대로 둔다.
  `-cm_hier` 는 covergroup 에 영향을 주지 않는다.

## 범위를 `tb_top.dut` 로 자르는 이유

`vip/coverage_report` 의 toggle 91% 는 DUT 가 없는 상태에서 TB 신호만 센 숫자였다.
interface 와 checker 비트가 섞이면 "TB 가 토글했나" 를 재게 된다. DUT 두 인스턴스만 남긴다.

```
tb_top.dut                          APB_v1_0          (wrapper, PRDATA/PREADY/PSLVERR mux)
tb_top.dut.APB_v1_0_S00_AXI_inst    APB_v1_0_S00_AXI  (bridge core, APB FSM)
```

## 기존 자극으로는 왜 안 채워지나

`axi_item` 제약과 smoke/random sequence 는 주소를 레지스터 맵 안에 묶는다.

| 비트 | smoke/stress 에서 | 원인 |
|---|---|---|
| `PADDR[31], [29:16], [15], [11:9], [0]` | 절대 안 움직임 | `addr[31:16]==16'h4000`, `addr[15]==0`, `addr[11:9]==0`, `addr[0]==0` |
| `write_reject`, `read_reject` | 항상 0 | 홀수 주소·반대 lane strobe 를 내는 sequence 가 없음 |
| wrapper 응답 mux `else` 가지 | 미도달 | unmapped 주소를 쓰는 양성 테스트가 없음 |

이 비트들은 **제외하지 않고 `bridge_toggle_sequence` 로 채운다.** DUT 는 `[14:12]` 만 디코드하므로
나머지 주소 비트를 흔들어도 scoreboard (`rejected_request`, `decode_select`) 가 전부 예측한다.

### `bridge_toggle_sequence` 가 하는 일

1. **데이터** : 3 slave × 2 lane 에 `FFFF`, `0000`, walking-1(16) 을 write→read.
   `WDATA[31:0]`, `PWDATA`, `PRDATA_UART/GPIO/TIMER`, `RDATA[31:0]` 모두 양방향.
2. **스트로브** : lane 별 `01/10/11`, 그리고 반대 lane·양쪽 lane strobe (reject → SLVERR, APB transfer 없음).
3. **PROT** : AxPROT 0..7 을 read/write 모두. `PPROT`/`apb_prot` 3 비트 양방향.
4. **주소 walk** : `0x4000_1000` 기준으로 비트 하나씩 XOR 해 write+read.
   연속 항목이 앞 비트를 되돌리므로 `AWADDR/ARADDR/axi_awaddr/axi_araddr/PADDR` 32 비트가 양방향.
   bit 0 = reject, bit 8 = APB error 주소, bit 12..14 = unmapped 코드 0/5 와 TIMER 코드 3, bit 30 = 0x4000 영역 이탈.
5. **unmapped 코드 0,4,5,6,7** : PSEL_* 없이 wrapper default sink 가 SLVERR 로 완료.
   주소 맵은 `PADDR[14:12]` 1 = UART, 2 = GPIO, 3 = TIMER 이고 나머지는 모두 unmapped 다.

약 330 transaction, 수십 µs. `bridge_toggle_test` 는 `enable_error=1` 로 돌려 `PSLVERR_*` 와 SLVERR 응답 경로도 토글시킨다.

## 실행

```
make regress      # smoke + stress + reset + strict_apb + unmapped + toggle -> coverage.vdb 에 test 별 -cm_name 으로 merge
make report       # 쌓인 coverage.vdb 를 merge 해서 coverage_report/dashboard.html (Toggle 열) + dashboard.txt
make cov          # 단일 test (TEST=...) run + report
make cov_wave     # Verdi coverage browser, exclusion 파일 preload
```

`bridge_strict_apb_test` 와 `bridge_unmapped_test` 는 수정 RTL 기준으로 둘 다 양성 테스트이며 regress 에 들어 있다.

## 제외 목록 (`bridge_toggle.el`) 과 기대되는 hole

| 대상 | 처리 | 사유 |
|---|---|---|
| `slv_reg0..3`, `reg_data_out`, `byte_index` | `.el` | Xilinx 템플릿 잔재. 선언만 있고 driver 전부 주석 |
| `*bresp[0]`, `*rresp[0]` (core·wrapper 6 개) | `.el` (`-cm_seqnoconst` 가 먼저 제거할 수도 있음) | OKAY(00)/SLVERR(10) 만 생성 |
| `PSTATE == 2'b11`, `case default` | FSM/branch hole, toggle 무관 | 도달 불가. Verdi 에서 제외 후 `.el` 재저장 |
| `s00_axi_aresetn` 1→0 | regress 로 해결 | `bridge_reset_test` 가 중간 reset 으로 채움 |

주소 맵 상수 비트는 `.el` 에 **올리지 않았다.** sweep 이 실제로 흔들기 때문이며, 그래야 "bridge 가 32 비트를 전부 전달한다" 가 검증된다.

## 리포트 읽는 법

- `dashboard.html` 의 Toggle 열이 DUT 기준 수치. Line/Cond/FSM/Branch 와 함께 본다.
- `hierarchy.html` 에서 wrapper 와 core 를 나눠 본다. 보통 core 가 낮다.
- 신호별 상세는 `mod*.html` Toggle 섹션. 0→1, 1→0 이 따로 표시되므로 한쪽만 빠진 비트를 찾는다.
- 새 hole 이 나오면 순서는 ① 자극 추가 가능? → sequence 보강, ② 설계상 불가? → `.el` 에 사유와 함께 추가.

## 검증 안 된 부분 (첫 실행 때 확인)

이 설정은 VCS/urg 를 돌리지 못한 상태에서 작성했다 (이 환경에서 shell 이 멈춤).

- `.el` 의 선언 문자열(`"reg slv_reg0[31:0]"` 등) 은 urg 가 찍는 형식을 추정한 것. 불일치 경고가 나오면
  `make cov_wave` 에서 같은 객체를 제외하고 Exclusion > Save 로 이 파일을 덮어쓴다.
- `-cm_hier` 의 `+tree` 문법과 `-cm_noconst`, `-cm_seqnoconst` 는 VCS W-2024.09 문서 기준. 거부되면 해당 옵션만 빼면 된다.

## 기존 TB 와의 충돌

- (2026-10-18 수정) `bridge_protocol_checker.sv` 의 `PPROT != 0` → `APB_PROT` 규칙은 PPROT 가 0 으로 묶여 있던
  원래 RTL 기준이라 제거했다. PPROT 값은 scoreboard 가 AxPROT 와 transaction 단위로 비교하고, 안정성·X 는
  checker 의 `current_apb` 가 계속 검사한다.
- (2026-10-18 수정) `bridge_unmapped_test` 는 driver timeout 을 기대하는 음성 테스트였으나, 수정 RTL 의 wrapper 가 default sink 로 SLVERR 을 반환하므로 unmapped read(코드 0)·unmapped write(코드 4) 가 SLVERR 로 완료되고 APB 전송이 없으며 이후 mapped read 가 정상인지 보는 양성 테스트로 바꿨다. `rejected_responses == 2`, `apb_checked == 1` 을 확인하고 regress 에 포함했다.
- `bridge_strict_apb_test` 의 주석은 read PSTRB 잔존을 기대하지만 RTL 은 read 에서 PSTRB 를 0 으로 지운다.

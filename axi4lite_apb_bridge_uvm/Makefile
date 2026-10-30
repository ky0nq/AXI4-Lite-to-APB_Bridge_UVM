# ============================================================
# AXI4-Lite -> APB bridge UVM - Synopsys VCS Makefile
#
# Project structure
# .
# ├── rtl/                APB_v1_0.v (DUT top), APB_v1_0_S00_AXI.v
# ├── tb/
# │   ├── interfaces/     axi_lite_if.sv (resetn + apply_reset 포함), apb_if.sv
# │   ├── bridge_pkg.sv   UVM class 파일들을 `include 한다 (class 파일은 따로 컴파일하지 않는다)
# │   ├── bridge_protocol_checker.sv
# │   └── tb_top.sv
# └── Makefile
#
# MobaXterm 에서 실행
#   1. MobaXterm -> Session -> SSH 로 서버에 접속한다
#      (Advanced SSH settings 의 X11-Forwarding 은 기본으로 켜져 있다 : Verdi 창이 MobaXterm X server 로 뜬다)
#   2. cd ~/odai2/axi_apb_uvm
#   3. make run            (make help 로 전체 target 확인)
#   vcs / verdi 가 PATH 에 없으면 평소 쓰는 VCS 환경 설정 (source ...) 을 먼저 한다
#
# Usage
#   make sim
#   make run  TEST=bridge_smoke_test
#   make run  TEST=bridge_stress_test NUM_RANDOM=500 SEED=7
#   make run  TEST=bridge_stress_test SEED=random (+ntb_random_seed_automatic)
#   make wave TEST=bridge_reset_test             (UCLI 로 wave.fsdb 덤프 -> Verdi)
#   make verdi                                   (이미 있는 wave.fsdb 만 다시 연다)
#   make cov
#   make cov_wave
#   make regress                                 (끝나면 make report 로 merge 된 coverage 확인)
#   make regress_seeds SEEDS="1 2 3"             (모든 test × seed 여러 개)
#   make clean
# ============================================================

SHELL       := /bin/bash

TEST        ?= bridge_smoke_test
VERBOSITY   ?= UVM_MEDIUM
TOP         ?= tb_top
SEED        ?= 1

# uvm = VCS 기본 UVM (1.1d). UVM 1.2 로 돌리려면 make clean 후 UVM_VER=uvm-1.2
UVM_VER     ?= uvm

# 추가 옵션 : VCS_OPTS 는 compile (바꾸면 make clean), SIM_OPTS 는 simv 실행에 붙는다
VCS_OPTS    ?=
SIM_OPTS    ?=

RTL_DIR     := rtl
TB_DIR      := tb
IF_DIR      := $(TB_DIR)/interfaces

SIMV        := simv
COMPILE_LOG := compile.log
RUN_LOG     := sim.log
REGRESS_LOG := regress.log

# report_phase 가 error/fatal 0 이고 응답을 1개 이상 검사했을 때 찍는 PASS 표시
PASS_ID     := BRIDGE_TEST_PASS

# ------------------------------------------------------------
# Waveform
#   tb 에 $fsdbDump 코드가 없으므로 UCLI do-file 로 덤프한다
# ------------------------------------------------------------
WAVE_FILE   := wave.fsdb
WAVE_SCOPE  ?= tb_top
WAVE_DEPTH  ?= 0
# memory / MDA / struct 까지 보려면 WAVE_OPTS=+all
WAVE_OPTS   ?=
DUMP_TCL    := dump.tcl

# ------------------------------------------------------------
# Coverage
# ------------------------------------------------------------
COV_DIR     := coverage.vdb
COV_REPORT  := coverage_report

# assert 는 넣지 않는다 : TB/DUT 에 SVA 가 없고 (checker 는 procedural), 잡히는 것은
# uvm_pkg 의 uvm_reg_map assert 2 개 (RAL 미사용이라 attempt 0) 뿐이라 SCORE 만 깎는다
COV_METRICS ?= line+cond+fsm+tgl+branch

# Toggle coverage 범위 / 제외 (cov/README.md)
#   COV_HIER : -cm_hier 범위 파일. tb_top.dut (RTL) 만 측정해서 TB 비트가 toggle % 를 희석하지 않게 한다
#   COV_EL   : urg / Verdi exclusion 파일. 설계상 상수인 bresp[0]/rresp[0] 와 dead 템플릿 reg 만 등록
#   -cm_noconst / -cm_seqnoconst : compile-time / sequential 상수를 toggle 에서 뺀다
COV_HIER    := cov/cm_hier.cfg
COV_EL      := cov/bridge_toggle.el
URG_EL      := $(if $(wildcard $(COV_EL)),-elfile $(COV_EL))

# ------------------------------------------------------------
# Source files
# ------------------------------------------------------------
RTL_SRCS := $(sort \
	$(wildcard $(RTL_DIR)/*.v) \
	$(wildcard $(RTL_DIR)/*.sv))

# bridge_pkg.sv includes UVM class files.
# Compile interface -> package -> checker -> top.
# tb/*.sv 를 wildcard 로 넣으면 include 전용 class 파일까지 컴파일되어 깨진다
TB_SRCS := \
	$(IF_DIR)/axi_lite_if.sv \
	$(IF_DIR)/apb_if.sv \
	$(TB_DIR)/bridge_pkg.sv \
	$(TB_DIR)/bridge_protocol_checker.sv \
	$(TB_DIR)/tb_top.sv

# Recompile when any TB file changes.
TB_DEPS := $(wildcard $(TB_DIR)/*.sv $(TB_DIR)/*.svh $(IF_DIR)/*.sv)

INC_DIRS := \
	+incdir+$(TB_DIR) \
	+incdir+$(IF_DIR) \
	+incdir+$(RTL_DIR)

# ------------------------------------------------------------
# Test plusargs (비어 있으면 안 붙는다)
# ------------------------------------------------------------
PLUSARGS :=
ifdef NUM_RANDOM
PLUSARGS += +NUM_RANDOM=$(NUM_RANDOM)
endif
ifdef TIMEOUT_CYCLES
PLUSARGS += +TIMEOUT_CYCLES=$(TIMEOUT_CYCLES)
endif
ifdef STRICT_APB
PLUSARGS += +STRICT_APB
endif

ifeq ($(SEED),random)
SEED_OPT := +ntb_random_seed_automatic
else
SEED_OPT := +ntb_random_seed=$(SEED)
endif

# ------------------------------------------------------------
# VCS options
# ------------------------------------------------------------
VCS_FLAGS := \
	-full64 \
	-sverilog \
	-ntb_opts $(UVM_VER) \
	-timescale=1ns/1ps \
	-debug_access+all \
	-kdb \
	-cm $(COV_METRICS) \
	-cm_dir $(COV_DIR) \
	-cm_hier $(COV_HIER) \
	-cm_noconst \
	-cm_seqnoconst \
	$(VCS_OPTS)

# $(call SIM_CMD,<test>,<log>) : simv 실행 명령
SIM_CMD = ./$(SIMV) \
	+UVM_TESTNAME=$(1) \
	+UVM_VERBOSITY=$(VERBOSITY) \
	$(SEED_OPT) \
	$(PLUSARGS) $(SIM_OPTS) \
	-cm $(COV_METRICS) \
	-cm_dir $(COV_DIR) \
	-cm_name $(1)_$(SEED) \
	-l $(2)

# $(call CHECK_LOG,<test>,<log>) : 로그에 PASS 표시가 있으면 PASS
CHECK_LOG = if grep -q "$(PASS_ID)" $(2); then \
		printf "[PASS] %-28s %s\n" "$(1)" "$(2)"; \
	else \
		printf "[FAIL] %-28s %s\n" "$(1)" "$(2)"; \
	fi

# 실패한 run 의 첫 UVM_ERROR / UVM_FATAL 몇 줄 (끝의 report 요약 줄은 뺀다)
FIRST_ERRORS = grep -E "^UVM_(ERROR|FATAL) [^:]" $(1) | head -n 5 || true

# Verdi 창은 MobaXterm 의 X server 로 뜬다. DISPLAY 가 비어 있으면 X11-Forwarding 이 꺼진 것
CHECK_X = @if [ -z "$$DISPLAY" ]; then \
		echo "[ERROR] DISPLAY 가 비어 있습니다. MobaXterm 세션 설정에서 X11-Forwarding 을 켜고 다시 접속하세요."; \
		exit 1; \
	fi

define URG_REPORT
urg -dir $(COV_DIR) -report $(COV_REPORT) -format both $(URG_EL)
@echo ""
@echo "========================================"
@echo " Coverage Report Generated"
@echo "========================================"
@echo "Database : $(COV_DIR)"
@echo "Report   : $(COV_REPORT)/dashboard.txt (text)"
@echo "           $(COV_REPORT)/dashboard.html"
@echo "========================================"
@if [ -f $(COV_REPORT)/dashboard.txt ]; then head -n 30 $(COV_REPORT)/dashboard.txt; fi
endef

.PHONY: all sim run wave verdi cov report cov_wave regress regress_seeds clean help

all: run

# ============================================================
# Compile + Elaborate
# ============================================================
sim: $(SIMV)

$(SIMV): $(RTL_SRCS) $(TB_DEPS) $(COV_HIER)
	@command -v vcs > /dev/null 2>&1 || { \
		echo "[ERROR] vcs 를 찾을 수 없습니다. MobaXterm 의 SSH 세션 (서버) 에서 실행하고, VCS 환경 설정을 먼저 하세요."; \
		exit 1; }
	vcs $(VCS_FLAGS) \
		$(INC_DIRS) \
		$(RTL_SRCS) \
		$(TB_SRCS) \
		-top $(TOP) \
		-o $(SIMV) \
		-l $(COMPILE_LOG)

# ============================================================
# Run UVM Simulation + Coverage
# ============================================================
run: sim
	$(call SIM_CMD,$(TEST),$(RUN_LOG))
	@echo ""
	@$(call CHECK_LOG,$(TEST),$(RUN_LOG))
	@$(call FIRST_ERRORS,$(RUN_LOG))

# ============================================================
# Dump Waveform (UCLI) + Open Verdi
# ============================================================
wave: sim
	@printf 'fsdbDumpfile "%s"\nfsdbDumpvars %s "%s" %s\nrun\nquit\n' \
		"$(WAVE_FILE)" "$(WAVE_DEPTH)" "$(WAVE_SCOPE)" "$(WAVE_OPTS)" > $(DUMP_TCL)
	$(call SIM_CMD,$(TEST),$(RUN_LOG)) -ucli -do $(DUMP_TCL)
	@echo ""
	@$(call CHECK_LOG,$(TEST),$(RUN_LOG))
	$(CHECK_X)
	verdi -dbdir $(SIMV).daidir -ssf $(WAVE_FILE) &

verdi:
	@if [ ! -f $(WAVE_FILE) ]; then echo "[ERROR] $(WAVE_FILE) 이 없습니다. 먼저 make wave"; exit 1; fi
	$(CHECK_X)
	verdi -dbdir $(SIMV).daidir -ssf $(WAVE_FILE) &

# ============================================================
# Generate Coverage Report
#   cov    : run 한 번 + report
#   report : 이미 쌓인 coverage.vdb (regress 등) 만 merge 해서 report
# ============================================================
cov: run
	$(URG_REPORT)

report:
	@if [ ! -d $(COV_DIR) ]; then echo "[ERROR] $(COV_DIR) 이 없습니다. 먼저 make run 또는 make regress"; exit 1; fi
	$(URG_REPORT)

# ============================================================
# Open Coverage with Verdi
# ============================================================
cov_wave: cov
	$(CHECK_X)
	verdi -cov -covdir $(COV_DIR) $(URG_EL) &

# ============================================================
# Regression : 모든 test 를 차례로 (같은 coverage.vdb 에 test 별 cm_name 으로 쌓인다)
#   bridge_toggle_test 와 bridge_reset_test 를 같이 돌려야 s00_axi_aresetn 1->0 toggle 까지 채워진다
#   bridge_unmapped_test 는 unmapped/reserved 주소가 SLVERR 로 완료되는지 보는 양성 test (2026-10-18 전환)
#   bridge_corner_test 는 wait>=16 완료, SETUP 중 reset (PSTATE 1->0), B/R 응답 대기 중 reset 을 채운다
#   bridge_overlap_test 는 read/write 를 동시에 걸어 B01 경계와 COND 165/168 overlap 4 행을 채운다
# ============================================================
REGRESS_TESTS ?= \
	bridge_smoke_test \
	bridge_stress_test \
	bridge_reset_test \
	bridge_strict_apb_test \
	bridge_unmapped_test \
	bridge_toggle_test \
	bridge_corner_test \
	bridge_overlap_test

regress: VERBOSITY = UVM_LOW
regress: sim
	@rm -f $(REGRESS_LOG)
	@for t in $(REGRESS_TESTS); do \
		echo "---- $$t (SEED=$(SEED))"; \
		$(call SIM_CMD,$${t},sim_$${t}.log) > /dev/null 2>&1; \
		$(call CHECK_LOG,$${t},sim_$${t}.log) | tee -a $(REGRESS_LOG); \
	done
	@echo ""
	@echo "==== Regression summary ($(REGRESS_LOG)) ===="
	@cat $(REGRESS_LOG)
	@echo "PASS $$(grep -c '^\[PASS\]' $(REGRESS_LOG)) / $$(wc -l < $(REGRESS_LOG))   (coverage merge : make report)"

# ============================================================
# Multi-seed regression : 모든 test 를 SEEDS 의 seed 마다 한 번씩
#   make regress_seeds                    (기본 seed 1~5)
#   make regress_seeds SEEDS="1 7 42 100"
#   cm_name 이 <test>_<seed> 라 seed 별로 coverage.vdb 에 따로 쌓이고 make report 가 merge 한다
#   로그는 sim_<test>_<seed>.log, 실패하면 make run TEST=<test> SEED=<seed> 로 재현
# ============================================================
SEEDS ?= 1 2 3 4 5

regress_seeds: VERBOSITY = UVM_LOW
regress_seeds: sim
	@rm -f $(REGRESS_LOG)
	@for s in $(SEEDS); do \
		for t in $(REGRESS_TESTS); do \
			echo "---- $$t (SEED=$$s)"; \
			./$(SIMV) +UVM_TESTNAME=$$t +UVM_VERBOSITY=$(VERBOSITY) \
				+ntb_random_seed=$$s $(PLUSARGS) $(SIM_OPTS) \
				-cm $(COV_METRICS) -cm_dir $(COV_DIR) -cm_name $${t}_$$s \
				-l sim_$${t}_$$s.log > /dev/null 2>&1; \
			$(call CHECK_LOG,$${t}_$$s,sim_$${t}_$$s.log) | tee -a $(REGRESS_LOG); \
		done; \
	done
	@echo ""
	@echo "==== Multi-seed regression summary ($(REGRESS_LOG)) ===="
	@grep '^\[FAIL\]' $(REGRESS_LOG) || echo "no failures"
	@echo "PASS $$(grep -c '^\[PASS\]' $(REGRESS_LOG)) / $$(wc -l < $(REGRESS_LOG))   seeds : $(SEEDS)   (coverage merge : make report)"

# ============================================================
# Clean
# ============================================================
clean:
	rm -rf \
		$(SIMV) \
		simv.daidir \
		csrc \
		ucli.key \
		vc_hdrs.h \
		DVEfiles \
		novas.conf \
		novas.rc \
		novas_dump.log \
		verdiLog \
		vdCovLog \
		verdi_config_file \
		AN.DB \
		$(DUMP_TCL) \
		$(COV_DIR) \
		$(COV_REPORT) \
		urgReport \
		*.vdb \
		*.vpd \
		*.vcd \
		*.fsdb \
		*.log

# ============================================================
# Help
# ============================================================
help:
	@echo "make sim"
	@echo "  Compile and elaborate with VCS"
	@echo ""
	@echo "make run TEST=<test> [SEED=n|random] [VERBOSITY=UVM_HIGH]"
	@echo "  Tests : bridge_smoke_test (default) bridge_stress_test bridge_reset_test"
	@echo "          bridge_strict_apb_test bridge_unmapped_test bridge_toggle_test bridge_corner_test"
	@echo "          bridge_overlap_test"
	@echo "          bridge_base_test"
	@echo ""
	@echo "make run TEST=bridge_stress_test NUM_RANDOM=500"
	@echo "make run TEST=bridge_reset_test TIMEOUT_CYCLES=400"
	@echo "make run STRICT_APB=1"
	@echo ""
	@echo "make wave TEST=<test> [WAVE_SCOPE=tb_top.dut] [WAVE_DEPTH=0] [WAVE_OPTS=+all]"
	@echo "  Dump wave.fsdb with UCLI and open it in Verdi (MobaXterm X11)"
	@echo "make verdi"
	@echo "  Re-open the existing wave.fsdb"
	@echo ""
	@echo "make cov      : run + coverage report ($(COV_REPORT)/dashboard.txt)"
	@echo "make report   : coverage report only (after make regress)"
	@echo "make cov_wave : open coverage in Verdi"
	@echo "make regress  : $(strip $(REGRESS_TESTS))"
	@echo "make regress_seeds [SEEDS=\"1 2 3 4 5\"] : every regress test once per seed"
	@echo "make clean    : remove generated files"

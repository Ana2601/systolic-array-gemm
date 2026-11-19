S     ?= 8
KMAX  ?= 64
TILES ?= 120
RTL   := rtl/systolic_pe.sv rtl/systolic_gemm.sv
BUILD := build

.PHONY: test lint synth clean

test:
	@mkdir -p $(BUILD)
	python3 scripts/gen_vectors.py $(S) $(KMAX) $(TILES) $(BUILD)/vectors.txt
	iverilog -g2012 -P tb_gemm.S=$(S) -P tb_gemm.KMAX=$(KMAX) -o $(BUILD)/tb.vvp $(RTL) tb/tb_gemm.sv
	vvp -n $(BUILD)/tb.vvp +vectors=$(BUILD)/vectors.txt

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module systolic_gemm $(RTL)

# PE-level cell count (the array is S*S copies of this)
synth:
	@mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv rtl/systolic_pe.sv; synth -top systolic_pe; tee -o $(BUILD)/synth_pe.txt stat"

clean:
	rm -rf $(BUILD)

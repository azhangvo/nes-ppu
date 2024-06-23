.PHONY: run clean format isa

SV_FILES=`cat sv_files.txt`

all: build

lint: isa
	verilator --lint-only --timing ${SV_FILES}

build: lint
	verilator --cc --exe --build --timing -j 0 --top-module ppu ${SV_FILES} ppu-tb.cpp -DLOAD_PROG

clean:
	rm -rf obj_dir

format:
	verible-verilog-format ${SV_FILES} --inplace && clang-format *.cpp -i
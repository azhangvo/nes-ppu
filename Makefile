.PHONY: run clean format

SV_FILES=`cat sv_files.txt`

all: build

lint:
	verilator --lint-only --timing ${SV_FILES}

build: 
	verilator --cc --exe --build --timing -j 0 --top-module nes_tb ${SV_FILES} nes-tb.cpp -DLOAD_PROG

run: build
	./obj_dir/Vnes_tb && python make_image.py

clean:
	rm -rf obj_dir
	rm -f output.png
	rm -f frame_buffer.hex

format:
	verible-verilog-format ${SV_FILES} --inplace && clang-format *.cpp -i
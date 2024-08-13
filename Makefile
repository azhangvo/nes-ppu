.PHONY: run clean clean_images format

SV_FILES=`cat sv_files.txt`
SDL_CFLAGS = `sdl2-config --cflags`
SDL_LDFLAGS = `sdl2-config --libs`

all: build

lint:
	verilator --lint-only --timing ${SV_FILES}

clean_images:
	rm -f output/hex/*.hex output/png/*.png

prep_dirs: clean_images
	mkdir -p output/hex output/png

build: 
	verilator --cc --exe --build --timing -j 0 --top-module nes_tb ${SV_FILES} ppu/ppu.sv nes-tb.cpp -DLOAD_PROG \
	-CFLAGS "${SDL_CFLAGS}" -LDFLAGS "${SDL_LDFLAGS}"

run: build prep_dirs
	./obj_dir/Vnes_tb
	make images

build_baseline:
	verilator --cc --exe --build --timing -j 0 --top-module nes_tb ${SV_FILES} lib/ppu.v nes-tb.cpp  -DLOAD_PROG \
	-CFLAGS "${SDL_CFLAGS}" -LDFLAGS "${SDL_LDFLAGS}"
	

run_baseline: build_baseline prep_dirs
	./obj_dir/Vnes_tb
	make images

images:
	$(foreach file, $(wildcard output/hex/*), python tools/make_image.py $(file) -o output/png/$(patsubst %.hex,%.png,$(notdir $(file)));)
	

clean:
	rm -rf obj_dir
	rm -rf output
	rm -f frame_buffer.hex

format:
	verible-verilog-format ${SV_FILES} --inplace && clang-format *.cpp -i
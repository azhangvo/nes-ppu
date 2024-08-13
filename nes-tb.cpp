#include "obj_dir/Vnes_tb.h"
#include "verilated.h"

#include <iostream>
#include <fstream>
#include <SDL.h>

using namespace std;

VerilatedContext *contextp;

const int H_RES = 256;
const int V_RES = 240;

int num_cycles = 0;

int rom_size;
int cpu_ram_size = 4096;
int chr_vram_size = 4096;
int total_size;
uint8_t *rom;
uint32_t rom_flags;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;



void reset_cycles(Vnes_tb* dut) {
    printf("Resetting cycles: %d -> %d\n", num_cycles, 0);
    num_cycles = 0;
    dut->cycle_count = num_cycles;
}

// void run(Vnes_tb* dut) {
//     while (1) {
//         int clk = 0;
//         dut->clk = clk;
//         dut->eval();
//         if(clk == 1) {
//             num_cycles++;
//             dut->cycle_count = num_cycles;
//             if (write_image(dut) != 0) return;
//         }
//         clk = ~clk;
//     }
// }

void run_for_cycles(Vnes_tb* dut, int cycles) {
    for (int i = 0; i < cycles * 2; i++) {
        dut->clk = i % 2;
        dut->eval();
        if(i % 2 == 1) {
            num_cycles++;
            dut->cycle_count = num_cycles;
        }
    }
}

// https://www.reddit.com/r/Roms/wiki/index/
// https://r-roms.github.io/
// https://ia802706.us.archive.org/view_archive.php?archive=/3/items/ni-roms/roms/Nintendo%20-%20Nintendo%20Entertainment%20System%20%28Headered%29.zip
int load_rom(int argc, char** argv) {

    // TODO This is just a placeholder, I know it isn't difficult but haven't bothered to use CLI yet
    const char* filepath = "roms/donkeykong.nes";
    
    // Open the file in binary mode
    std::ifstream file(filepath, std::ios::binary | std::ios::ate);
    
    if (!file.is_open()) {
        std::cerr << "Failed to open file: " << filepath << std::endl;
        return 0;
    }

    // Determine the size of the file
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    // Read header shit
    uint8_t header[16];
    file.read(reinterpret_cast<char*>(header), 16);
    
    if (file.gcount() != 16) {
        std::cerr << "Failed to read iNES header." << std::endl;
        return 1;
    }

    // https://www.nesdev.org/wiki/INES#Flags_7
    printf("Header 4, 5, 6, 7: %u, %u, %u, %u\n", header[4], header[5], header[6], header[7]);

    uint8_t mapper_low = (header[6] >> 4) & 0x0F;  // Low nibble from byte 6
    uint8_t mapper_high = (header[7] >> 4) & 0x0F;  // High nibble from byte 7

    uint8_t mapper_number = (mapper_high << 4) | mapper_low;

    std::cout << "Mapper Number: " << static_cast<int>(mapper_number) << std::endl;
    uint8_t prg_size = header[4] & 0x07;
    uint8_t chr_size = header[5] & 0x07;
    printf("prg_size: %u, chr_size: %u\n", prg_size, chr_size);

    // Flags to give to memory mapper
    rom_flags = mapper_number | ((prg_size - 1) << 8) | ((chr_size - 1) << 11) | (1 << 15);
    printf("mapper flags: %u\n", rom_flags);

    std::streamsize data_size = size - 16;

    // Allocate memory for the file content
    rom_size = data_size;
    rom = new uint8_t[rom_size + cpu_ram_size + chr_vram_size];
    total_size = rom_size + cpu_ram_size + chr_vram_size;
    fill(rom + rom_size, rom + total_size, 0);

    // Read the file content into the allocated memory
    if (!file.read(reinterpret_cast<char*>(rom), data_size)) {
        std::cerr << "Failed to read file: " << filepath << std::endl;
        delete[] rom;
        return 0;
    }

    printf("ROM file size in bytes: %u\n", data_size);
    // for (int i = 0; i < size; i++) {
    //     printf("%c", rom_char[i]);
    // }
    // printf("\n");

    // Close the file
    file.close();
    return 1;
}

int main(int argc, char** argv) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    Pixel screenbuffer1[H_RES*V_RES] = {{0}};
    Pixel screenbuffer2[H_RES*V_RES] = {{0}};
    Pixel (*screenbuffer)[H_RES*V_RES] = &screenbuffer1;
    uintptr_t idea = (uintptr_t)&screenbuffer1 ^ (uintptr_t)&screenbuffer2;

    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    sdl_window = SDL_CreateWindow("Square", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_RES, V_RES, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        printf("Renderer creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET, H_RES, V_RES);
    if (!sdl_texture) {
        printf("Texture creation failed: %s\n", SDL_GetError());
        return 1;
    }

    // Load the rom
    if (!load_rom(argc, argv)) {
        printf("Rom loading failed!\n");
        return 1;
    }

    // reference SDL keyboard state array: https://wiki.libsdl.org/SDL_GetKeyboardState
    const Uint8 *keyb_state = SDL_GetKeyboardState(NULL);

    printf("Simulation running. Press 'Q' in simulation window to quit.\n\n");

    contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    auto *dut = new Vnes_tb{contextp};
    Verilated::traceEverOn(true);

    // dut->write_enable = 0;
    // dut->reset = 1;
    // dut->ce = 0;
    // run_for_cycles(dut, 1);

    dut->reset = 0;
    // run_for_cycles(dut, 2);
    
    dut->ce = 1;

    // reset_cycles(dut);

    // Give mapper flags to the nes module
    dut->mapper_flags = rom_flags;

    // write_image(dut);

    uint64_t start_ticks = SDL_GetPerformanceCounter();
    uint64_t frame_count = 0;

    bool quit = false;

    // What did module request on the last cycle
    // I know this + related logic can be cleaner, but should be correct for now
    int prev_memory_addr = 0;
    bool prev_do_cpu_read = false, prev_do_ppu_read = false;

    while (!quit) {
        if(frame_count >= 3) {
            break;
        }
        dut->clk ^= 1;

        // Give the data the NES wants to read

        // printf("before mem_addr: %i, mem_write: %i, mem_read_cpu: %i, mem_read_ppu: %i\n", prev_memory_addr, dut->memory_write, dut->memory_read_cpu, dut->memory_read_ppu);
        // if (prev_memory_addr < total_size && rom[prev_memory_addr] != 0) printf("nonzero data at %u: %u\n", prev_memory_addr, rom[prev_memory_addr]);
        if (prev_do_cpu_read) {
            dut->memory_din_cpu = prev_memory_addr < total_size ? rom[prev_memory_addr] : 0;
        } else if (prev_do_ppu_read) {
            dut->memory_din_ppu = prev_memory_addr < total_size ? rom[prev_memory_addr] : 0;
        }

        dut->eval();
        if(dut->clk == 1) {
            num_cycles++;
            dut->cycle_count = num_cycles;

            if (dut->vga_scanline < V_RES && dut->vga_cycle < H_RES) {
                Pixel* p = &(*screenbuffer)[dut->vga_scanline*H_RES + dut->vga_cycle];
                p->a = 0xFF;  // transparency
                p->b = dut->vga_b * 85;
                p->g = dut->vga_g * 85;
                p->r = dut->vga_r * 85;
            }

            // Process memory access requests
            prev_do_cpu_read = false;
            prev_do_ppu_read = false;

            // Handle addressing types - I have no idea how to support this generically yet for all types of memory mappers
            // although I don't feel it's necessary to support every type.
            // Pretty sure there are some commonly used types - I've tried donkey kong and solar wars, both use Mapper28 in mmu.v
            // TODO - this is incorrect logic for any files with more than 1 pgr page
            // Reference https://www.nesdev.org/wiki/INES
            int memory_addr = dut->memory_addr;
            if (memory_addr >= 3932160) {
                // 1111, CARTRAM not implemented
                printf("CARTRAM not supported yet !!mem_addr: %i, dut_mem_addr: %u, mem_write: %i, mem_read_cpu: %i, mem_read_ppu: %i, rom data: %i, write data: %i\n", memory_addr, dut->memory_addr, dut->memory_write, dut->memory_read_cpu, dut->memory_read_ppu, memory_addr < total_size ? rom[memory_addr] : 0, dut->memory_dout);
            } else if (memory_addr >= 3670016) {
                // 1110, CPU-RAM
                memory_addr = rom_size + (memory_addr & 0x3FFFF);
            } else if (memory_addr >= 3145728) {
                // 1100, CHR-VRAM
                memory_addr = rom_size + cpu_ram_size + (memory_addr & 0x7FF);
            } else if (memory_addr >= 2097152) {
                // 1000, CHR
                memory_addr = 16384 + (memory_addr & 0xFFFFF);
            } else {
                // 0000, PRG
                memory_addr = memory_addr;
            }

            // Write to RAM if applicable, otherwise set read vars

            // printf("mem_addr: %i, dut_mem_addr: %u, mem_write: %i, mem_read_cpu: %i, mem_read_ppu: %i, rom data: %i, write data: %i\n", memory_addr, dut->memory_addr, dut->memory_write, dut->memory_read_cpu, dut->memory_read_ppu, memory_addr < total_size ? rom[memory_addr] : 0, dut->memory_dout);
            // if (num_cycles > 100000) break;
            if (memory_addr < total_size) {
                if (dut->memory_write) {
                    rom[memory_addr] = dut->memory_dout;
                } else if (dut->memory_read_cpu) {
                    prev_do_cpu_read = true;
                } else if (dut->memory_read_ppu) {
                    prev_do_ppu_read = true;
                }
            }

            prev_memory_addr = memory_addr;

            //printf("rgb: %x, %x, %x", p->r, p->g, p->b);
            bool updated = false;

            if (dut->vga_scanline == V_RES && dut->vga_cycle == 0) {
            // if (dut->vga_cycle == 0) {
                //printf("scanline, cycle: %d, %d\n", dut->vga_scanline, dut->vga_cycle);
                // check for quit event
                screenbuffer = (Pixel (*)[H_RES*V_RES])((uintptr_t)screenbuffer ^ idea);
                frame_count++;
                updated = true;
            }

            if(!(num_cycles % 1000000) || updated) {
                SDL_Event e;
                if (SDL_PollEvent(&e)) {
                    if (e.type == SDL_QUIT) {
                        quit = true;
                    }
                }

                if (keyb_state[SDL_SCANCODE_Q]) quit = true;  // quit if user presses 'Q'

                SDL_UpdateTexture(sdl_texture, NULL, *(Pixel (*)[H_RES*V_RES])((uintptr_t)screenbuffer ^ idea), H_RES*sizeof(Pixel));
                SDL_RenderClear(sdl_renderer);
                SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
                SDL_RenderPresent(sdl_renderer);
            }
        }
    }

    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f\n", fps);

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();

    fflush(stdout);
    delete contextp;
    delete rom;
}
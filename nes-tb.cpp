#include "obj_dir/Vnes_tb.h"
#include "verilated.h"

#include <iostream>
#include <fstream>
#include <SDL.h>

using namespace std;

VerilatedContext *contextp;

const int H_RES = 256;
const int V_RES = 240;

const int RIGHT = 7;
const int LEFT = 6;
const int DOWN = 5;
const int UP = 4;
const int START = 3;
const int SELECT = 2;
const int B = 1;
const int A = 0;

const int PALETTE [64] {
    0x555555, 0x001773, 0x000786, 0x2e0578, 0x59024d, 0x720011, 0x6e0000, 0x4c0800, 0x171b00, 0x002a00, 0x003100, 0x002e08, 0x002645, 0x000000, 0x000000, 0x000000,
    0xa5a5a5, 0x0057c6, 0x223fe5, 0x6e28d9, 0xae1aa6, 0xd21759, 0xd12107, 0xa73700, 0x635100, 0x186700, 0x007200, 0x007331, 0x006a84, 0x000000, 0x000000, 0x000000,
    0xfeffff, 0x2fa8ff, 0x5d81ff, 0x9c70ff, 0xf772ff, 0xff77bd, 0xff7e75, 0xff8a2b, 0xcda000, 0x81b802, 0x3dc830, 0x12cd7b, 0x0dc5d0, 0x3c3c3c, 0x000000, 0x000000,
    0xfeffff, 0xa4deff, 0xb1c8ff, 0xccbeff, 0xf4c3ff, 0xffc5ea, 0xffc7c9, 0xffcdaa, 0xefd696, 0xd0e095, 0xb3e7a5, 0x9feac3, 0x91e8e6, 0xafafaf, 0x000000, 0x000000
};

int num_cycles = 0;

int num_prg, num_chr;
int rom_size;
int cpu_ram_size = 4096;
int chr_vram_size = 4096;
int total_size;
uint8_t *memory;
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


int load_rom(int argc, char** argv) {

    // TODO can change to use CLI
    const char* filepath = "roms/supermariobros.nes";
    
    // Open file and get size
    std::ifstream file(filepath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        printf("Failed to open file: %s\n", filepath);
        return 0;
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    // Read header
    uint8_t header[16];
    file.read(reinterpret_cast<char*>(header), 16);
    if (file.gcount() != 16) {
        printf("Failed to read iNES header.\n");
        return 1;
    }
    printf("Header 4, 5, 6, 7: %u, %u, %u, %u\n", header[4], header[5], header[6], header[7]);

    // Get mapper number
    uint8_t mapper_low = (header[6] >> 4) & 0x0F;  // Low nibble from byte 6
    uint8_t mapper_high = (header[7] >> 4) & 0x0F;  // High nibble from byte 7
    uint8_t mapper_number = (mapper_high << 4) | mapper_low;
    printf("Mapper Number: %u\n", mapper_number);

    // Get number of pages
    num_prg = header[4] & 0x07;
    num_chr = header[5] & 0x07;
    printf("prg_size: %u, chr_size: %u\n", num_prg, num_chr);

    bool vertical_mirroring = header[6] & 0x01;

    // Flags to give to memory mapper
    rom_flags = mapper_number | ((num_prg - 1) << 8) | ((num_chr - 1) << 11) | (vertical_mirroring << 14) | (1 << 15);
    printf("mapper flags: %u\n", rom_flags);

    std::streamsize data_size = size - 16;

    // Allocate memory for the file content
    rom_size = data_size;
    memory = new uint8_t[rom_size + cpu_ram_size + chr_vram_size];
    total_size = rom_size + cpu_ram_size + chr_vram_size;
    fill(memory + rom_size, memory + total_size, 0);

    // Read the file content into the allocated memory
    if (!file.read(reinterpret_cast<char*>(memory), data_size)) {
        printf("Failed to read file: %s\n", filepath);
        delete[] memory;
        return 0;
    }
    printf("ROM file size in bytes: %u\n", data_size);

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

    // Give mapper flags to the nes module
    dut->mapper_flags = rom_flags;

    dut->write_enable = 0;
    dut->reset = 1;
    dut->ce = 0;
    run_for_cycles(dut, 100);

    dut->reset = 0;    
    dut->ce = 1;

    uint64_t start_ticks = SDL_GetPerformanceCounter();
    uint64_t frame_count = 0;

    bool quit = false;

    // What did module request on the last cycle
    int prev_memory_addr = 0;
    bool prev_do_cpu_read = false, prev_do_ppu_read = false;

    while (!quit) {
        // if(frame_count >= 30) {
        //     break;
        // }
        dut->clk ^= 1;

        // Give the data the NES wants to read
        if (prev_do_cpu_read) {
            dut->memory_din_cpu = prev_memory_addr < total_size ? memory[prev_memory_addr] : 0;
        } else if (prev_do_ppu_read) {
            dut->memory_din_ppu = prev_memory_addr < total_size ? memory[prev_memory_addr] : 0;
        }

        dut->eval();
        if(dut->clk == 1) {
            num_cycles++;
            dut->cycle_count = num_cycles;

            if (dut->vga_scanline < V_RES && dut->vga_cycle < H_RES) {
                Pixel* p = &(*screenbuffer)[dut->vga_scanline*H_RES + dut->vga_cycle];

                int idx = (dut->vga_luma * 16) + dut->vga_hue;
                
                p->a = 0xFF;  // transparency
                p->b = (PALETTE[idx]) & 0xff;
                p->g = (PALETTE[idx] >> 8) & 0xff;
                p->r = (PALETTE[idx] >> 16) & 0xff;
            }

            // Process memory access requests
            prev_do_cpu_read = false;
            prev_do_ppu_read = false;

            // Supporting different addressing types - enough for emulation
            int memory_addr = dut->memory_addr;
            if (memory_addr >= 3932160) {
                // 1111, CARTRAM not implemented
                printf("CARTRAM not supported yet !!mem_addr: %i, dut_mem_addr: %u, mem_write: %i, mem_read_cpu: %i, mem_read_ppu: %i, rom data: %i, write data: %i\n", memory_addr, dut->memory_addr, dut->memory_write, dut->memory_read_cpu, dut->memory_read_ppu, memory_addr < total_size ? memory[memory_addr] : 0, dut->memory_dout);
            } else if (memory_addr >= 3670016) {
                // 1110, CPU-RAM
                memory_addr = rom_size + (memory_addr & 0x3FFFF);
            } else if (memory_addr >= 3145728) {
                // 1100, CHR-VRAM
                memory_addr = rom_size + cpu_ram_size + (memory_addr & 0x7FF);
            } else if (memory_addr >= 2097152) {
                // 1000, CHR
                memory_addr = num_prg * 16384 + (memory_addr & 0xFFFFF);
            } else {
                // 0000, PRG
                memory_addr = memory_addr;
            }

            // Write to RAM if applicable, otherwise set read vars
            if (memory_addr < total_size) {
                if (dut->memory_write) {
                    memory[memory_addr] = dut->memory_dout;
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
                uint8_t inp1 = 0;
                uint8_t inp2 = 0;
                if (SDL_PollEvent(&e)) {
                    if (e.type == SDL_QUIT) {
                        quit = true;
                    }

                    if (e.type == SDL_KEYDOWN) {
                        if (e.key.keysym.sym == SDLK_DOWN) {
                            inp1 |= (1 << DOWN);
                        }
                        if (e.key.keysym.sym == SDLK_UP) {
                            inp1 |= (1 << UP);
                        }
                        if (e.key.keysym.sym == SDLK_LEFT) {
                            inp1 |= (1 << LEFT);
                        }
                        if (e.key.keysym.sym == SDLK_RIGHT) {
                            inp1 |= (1 << RIGHT);
                        }
                        if (e.key.keysym.sym == SDLK_a) {
                            inp1 |= (1 << A);
                        }
                        if (e.key.keysym.sym == SDLK_s) {
                            inp1 |= (1 << B);
                        }
                        if (e.key.keysym.sym == SDLK_d) {
                            inp1 |= (1 << START);
                        }
                        if (e.key.keysym.sym == SDLK_f) {
                            inp1 |= (1 << SELECT);
                        }
                        dut->joypad_data1 = inp1;
                        dut->joypad_data2 = inp2;
                        // printf("%x\n", inp1);

                    } else if (e.type == SDL_KEYUP) {
                        if (e.key.keysym.sym == SDLK_DOWN) {
                            inp1 &= ~(1 << DOWN);
                        }
                        if (e.key.keysym.sym == SDLK_UP) {
                            inp1 &= ~(1 << UP);
                        }
                        if (e.key.keysym.sym == SDLK_LEFT) {
                            inp1 &= ~(1 << LEFT);
                        }
                        if (e.key.keysym.sym == SDLK_RIGHT) {
                            inp1 &= ~(1 << RIGHT);
                        }
                        if (e.key.keysym.sym == SDLK_a) {
                            inp1 &= ~(1 << A);
                        }
                        if (e.key.keysym.sym == SDLK_s) {
                            inp1 &= ~(1 << B);
                        }
                        if (e.key.keysym.sym == SDLK_d) {
                            inp1 &= ~(1 << START);
                        }
                        if (e.key.keysym.sym == SDLK_f) {
                            inp1 &= ~(1 << SELECT);
                        }
                        dut->joypad_data1 = inp1;
                        dut->joypad_data2 = inp2;
                        // printf("%x\n", inp1);
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
    delete memory;
}
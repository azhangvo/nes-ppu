#include "obj_dir/Vnes_tb.h"
#include "verilated.h"

#include <iostream>
#include <SDL.h>

using namespace std;

VerilatedContext *contextp;

const int H_RES = 256;
const int V_RES = 240;

int num_cycles = 0;

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

int main(int argc, char** argv) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    Pixel screenbuffer[H_RES*V_RES] = {{0}};

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

    // reference SDL keyboard state array: https://wiki.libsdl.org/SDL_GetKeyboardState
    const Uint8 *keyb_state = SDL_GetKeyboardState(NULL);

    printf("Simulation running. Press 'Q' in simulation window to quit.\n\n");

    contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    auto *dut = new Vnes_tb{contextp};
    Verilated::traceEverOn(true);

    // dut->write_enable = 0;
    dut->reset = 1;
    dut->ce = 0;
    run_for_cycles(dut, 1);

    dut->reset = 0;
    run_for_cycles(dut, 2);
    
    dut->ce = 1;

    reset_cycles(dut);

    // write_image(dut);

    uint64_t start_ticks = SDL_GetPerformanceCounter();
    uint64_t frame_count = 0;

    bool quit = false;


    while (!quit) {
        dut->clk ^= 1;
        dut->eval();
        if(dut->clk == 1) {
            num_cycles++;
            dut->cycle_count = num_cycles;

            if (dut->vga_scanline < V_RES && dut->vga_cycle < H_RES) {
                Pixel* p = &screenbuffer[dut->vga_scanline*H_RES + dut->vga_cycle];
                p->a = 0xFF;  // transparency
                p->b = dut->vga_b * 85;
                p->g = dut->vga_g * 85;
                p->r = dut->vga_r * 85;
            }
            //printf("rgb: %x, %x, %x", p->r, p->g, p->b);

            if (dut->vga_scanline == V_RES && dut->vga_cycle == 0) {
                //printf("scanline, cycle: %d, %d\n", dut->vga_scanline, dut->vga_cycle);
                // check for quit event
                SDL_Event e;
                if (SDL_PollEvent(&e)) {
                    if (e.type == SDL_QUIT) {
                        quit = true;
                    }
                }

                if (keyb_state[SDL_SCANCODE_Q]) quit = true;  // quit if user presses 'Q'

                SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES*sizeof(Pixel));
                SDL_RenderClear(sdl_renderer);
                SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
                SDL_RenderPresent(sdl_renderer);
                frame_count++;
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
}
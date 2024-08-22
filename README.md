# CS 350 Final Project - NES in Verilog
Spring 2024: Advanced Comp. Arch. - Dr. Siddartha Chatterjee

Group: Raghav Rangan (rvr376), Kevin Zhao, Arthur Zhang

## Intro

Our goal with this project was to implement the Picture Processing Unit (PPU) of the Nintendo Entertainment System (NES). We wanted the experience of creating a simple GPU, with the requirements of having some parallelism, graphical calculation, and display output. Given that the NES' PPU has a clear, well-defined spec, and a lot of work has been done with recreating the NES, we chose to implement this.

## Our Implementation

We based our code on the following repository which implemented an NES system to be run on an FPGA: [repo](https://github.com/strigeus/fpganes/tree/master).

We used the CPU, Memory Mapper, and most of the mainboard logic implemented in the repo as is, and rewrote the PPU from scratch, based only on the original design's input/output port signatures. Since we are not running our implementation on FPGA, major changes were made to `nes_tb.v`, to support simulating display and input. We also wrote our own custom ROM loader to place game code in memory, since we use an array to simulate RAM.

Our final design was able to successfully render and play **Donkey Kong** and multiple other games, achieving our original goal of being able to run + play NES games.

### Display and Input

We use SDL2 to simulate both display and input. For display, the PPU outputs a `color` vector per pixel to be displayed, whose coordinates are represented by the values `scanline` and `cycle` which is used to index into a palette array, containing RGB hex codes for various colors used. We simply create a display window using SDL2 and write each pixel to a frame buffer, which is flushed to the window every time a full frame is written. Through this, we are able to achieve 20-40 FPS (machine dependent), which is more than playable.

Input is also handled by SDL2, and we use keyboard input to simulate an NES controller, with each of the 8 buttons being mapped to a key. The controllers (2 of them) write to address `$4016` and `$4017` respectively, to indicate to the NES that it should strobe the controllers' states. Once these adresses go low, the states are captured in two shift registers, which the NES reads bit-by-bit. To simulate this, we use SDL2 to capture the keyboard input and create an 8-long vector of press states, which is passed as the controller state to the NES. We provide functionality for player 1, though adding player 2 functionality just involves choosing a set of keys to represent inputs and reading their states on keypress.

### ROM Loading and Memory Access

To run a game with our NES modules, we need to load a game ROM. I got game romes from archive.org (specifically [here](https://ia802706.us.archive.org/view_archive.php?archive=/3/items/ni-roms/roms/Nintendo%20-%20Nintendo%20Entertainment%20System%20%28Headered%29.zip) for relevant NES ones). We read the 16 byte header to extract the mapper number and number of pages ([reference](https://www.nesdev.org/wiki/INES#Flags_7) for header information). Then, we copy the rest of the ROM into our memory block. In this design, we use one memory block to store the ROM, RAM, etc. and just index into it accordingly - big array with ROM, CPU-RAM, CHR-VRAM placed one after the other.

When simulation starts, we pass in the correct flags for the memory mapper according to the iNES header. We then pass a reset signal and program execution starts at the reset vector location ($FFFC-$FFFD). During simulation, we keep track of requests for memory read and write operations, and perform the appropriate actions/return the correct data to the nes module. For memory accesses, we differentiate between the different types of accesses to index into the right place in memory. 

### PPU Implementation

The first step in implementing the PPU was to understand the PPU inputs. This is rather poorly documented on the nesdev website, but there are 4 main parts.

1. Clock - the PPU is clocked at 3x the rate of the CPU
2. DBUS - the PPU receives data through MMIO from the CPU side, which appears as bus read/write input no the PPU side. This looks like a 3 bit address, a read/write flag, and a 8 bit data in channel.
3. VRAM - the PPU interfaces with external VRAM, which is used to store background nametable information, background attribute information, and sprite and background patterns. As it is external, the PPU can read and write from it with a read/write flag, a 8 bit data in channel, and a 8 bit data out channel.
4. OAM - the PPU also has internal sprite memory, which is stored internally. This is not an input under this setup, but we've programmed the memory reads as if only one read/write is possible per cycle.

Using these inputs, we used the NES docs to replicate the PPU design, using the original repo's PPU implementation as a final baseline to compare outputs against. The rough implementation details are as follows:

#### VBlank

The NES PPU takes ~85k cycles per frame. It's generally split up into 262 scanlines and 341 cycles, of which scanlines 0-239 and cycles 1-256 are visible. Staring on scanline 240, the PPU enters vblank, which is a phase where it is not rendering and it is safe for the CPU to write to the PPU. Here, we process the inputs from the bus and store important information such as the x and y scroll, nametable addresses, along with other parameters. We also allow the CPU to write and read from vram and OAM so it can update background and sprites. (We also technically allow this outside of vblank as well, according to normal PPU spec, but it is generally not recommended for programs to write outside of vblank as this may cause artifacts).

#### Background Rendering

To perform rendering for the background, the first step is to retrieve an address from the nametable in VRAM using the x and y coordinate of the pixel we want to render. This address points toward a location in VRAM that stores the patterns and colors in the background in that location. Then, another byte is retrieved from the attribute table, using the x and y coordinates of the pixel, and two bits are selected from the byte by using the x and y coordinates again. Then, using the previous address, two bytes are retrieved from VRAM that store the actual pattern for that pixel. Lastly, these values are combined to create a 4 bit color representation.

In reality, we retrieve the memory for the pixel 2 tiles or 16 pixels in the future, and then put this into a shift register so that we can perform the accesses in time. Additionally, every access takes 2 cycles, and retrieves 8 pixels worth of information, which means it takes 8 cycles to retrieve the 4 bytes needed for the next 8 pixels. This also means that before every scanline, we use cycles 320-336 to retrieve the first two tiles of the next scanline in advance.

#### Sprite Rendering

Sprite rendering is somewhat similar to background rendering, but differs in determining which sprite to render. First, while the background is rendering for each scanline, the sprites that will be visible on the next scanline are being fetched. This is done by essentially looping through the list of 64 sprites stored in OAM and retriving the first 8 sprites that would be visible on the next scanline by y coordinate. For these sprites that would be visible, their data, 4 bytes each, are transfered into a secondary OAM that stores 32 total bytes of data, 4 x 8 bytes. Then, from cycles 257-320, the sprite patterns are retrieved from VRAM (according to byte 1 of their data, which stores the address), and kept latched in registers. Then, on the next scanline, each sprite determines if it should produce a pixel, and if so, it produces one based on the latched pattern registers, and also attribute information provided by byte 2 of their data. Each sprite outputs a 5 bit pixel, where the last four bits are the same as described above, but the most significant bit also represents if it is visible (it exists and is not transparent).

#### Pixel Muxing

To choose the pixels, sprites are given priority over the background if they are not transparent, and sprites are given priority in the order that they were loaded in. If no sprites are loaded, it defaults to the background. This pixel is then translated using an internal palette to a different format, which gets outputted as a 6 bit color to the CPU.

### Summary of Contributions

Files written:
- `ppu/ppu.v`: Written from scratch PPU, only uses I/O port signature from `lib/ppu.v`
- `nes-tb.cpp`: Custom testbench, contains all the simulation logic (display + inputs) and ROM loading logic
- `nes-tb.v`: Adapter testbench for verilator control

Files reused:
- `lib/cpu.v`
- `lib/MicroCode.v`: ISA for CPU
- `lib/nes.v`: mainboard logic
- `lib/mmu.v`: memory mappers
- `lib/compat.v`: component / gate logic
- `apu.v`: Audio Processing unit, used for controllers

**Use `make run` to run our impl**

## Conclusions

Through this project we were able to gain a better understanding of graphical circuitry, and how development in Verilog works. The memory loading was also a challenging part of the design, and it taught us a lot about understanding a spec well, and building a compliant design. A fun extension of what we have accomplished would be to simulate the APU, and provide a signal to the laptop speakers.

A huge thank you to Dr. Chatterjee for making a fun and interesting class, and giving us the extension required for us to be able to accomplish this. 
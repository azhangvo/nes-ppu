# CS 350 Final Project - NES in Verilog
Spring 2024: Advanced Comp. Arch. - Dr. Siddartha Chatterjee

Group: Raghav Rangan (rvr376), Kevin Zhao, Arthur Zhang

## Intro

Our goal with this project was to implement the Picture Processing Unit (PPU) of the Nintendo Entertainment System (NES). We wanted the experience of creating a simple GPU, with the requirements of having some parallelism, graphical calculation, and display output. Given that the NES' PPU has a clear, well-defined spec, and a lot of work has been done with recreating the NES, we chose to implement this.

## Our Implementation

We based our code on the followign repository which implemented an NES system to be run on an FPGA: [repo](https://github.com/strigeus/fpganes/tree/master).

We used the CPU, Memory Mapper, and most of the mainboard logic implemented in the repo as is, and rewrote the PPU from scratch, based only on the original design's input/output port signatures. Since we are not running our implementation on FPGA, major changes were made to `nes_tb.v`, to support simulating display and input. We also wrote our own custom ROM loader to place game code in memory, since we use an array to simulate RAM.

Our final design was able to successfully render and play **Donkey Kong** and **Super Mario Bros**, and is set up to have any NES ROM loaded and played, which goes beyond our original scope of just being able to handle **SMB**.

### Display and Input

We use SDL2 to simulate both display and input. For display, the PPU outputs a `color` vector, which is an RGB value for a single pixel, whose coordinates are represented by the values `scanline` and `cycle`. We simply create a display window using SDL2 and write each pixel to a frame buffer, which is flushed to the window every time a full frame is written. Through this, we are able to achieve 20-40 FPS (machine dependent), which is more than playable.

Input is also handled by SDL2, and we use keyboard input to simulate an NES controller, with each of the 8 buttons being mapped to a key. The controllers (2 of them) write to address `$4016` and `$4017` respectively, to indicate to the NES that it should strobe the controllers' states. Once these adresses go low, the states are captured in two shift registers, which the NES reads bit-by-bit. To simulate this, we use SDL2 to capture the keyboard input and create an 8-long vector of press states, which is passed as the controller state to the NES. We also write to the previously mentioned addresses to capture this provided vector and handle inputs in `NES.v`.

### ROM Loading and Memory Access

To run a game with our NES modules, we need to load a game ROM. I got game romes from archive.org (specifically [here](https://ia802706.us.archive.org/view_archive.php?archive=/3/items/ni-roms/roms/Nintendo%20-%20Nintendo%20Entertainment%20System%20%28Headered%29.zip) for relevant NES ones). We read the 16 byte header to extract the mapper number and number of pages ([reference](https://www.nesdev.org/wiki/INES#Flags_7) for header information). Then, we copy the rest of the ROM into our memory block. In this design, we use one memory block to store the ROM, RAM, etc. and just index into it accordingly - big array with ROM, CPU-RAM, CHR-VRAM placed one after the other.

During simulation, we keep track of requests for memory read and write operations, and perform the appropriate actions/return the correct data to the nes module. For memory accesses, we differentiate between the different types of accesses and index into the right place in memory. 

### PPU Implementation

(TODO: Arthur)

## Conclusions

Through this project we were able to gain a better understanding of graphical circuitry, and how development in Verilog works. The memory loading was also a challenging part of the design, and it taught us a lot about understanding a spec well, and building a compliant design. A fun extension of what we have accomplished would be to simulate the APU, and provide a signal to the laptop speakers.

A huge thank you to Dr. Chatterjee for making a fun and interesting class, and giving us the extension required for us to be able to accomplish this. 
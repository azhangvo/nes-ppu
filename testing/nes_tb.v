module nes_tb;
    reg clk;
    reg reset;
    reg ce;
    reg [31:0] mapper_flags;
    wire [15:0] sample;
    wire [5:0] color;
    wire joypad_strobe;
    wire [1:0] joypad_clock;
    reg [1:0] joypad_data;
    reg [4:0] audio_channels;
    wire [21:0] memory_addr;
    wire memory_read_cpu;
    reg [7:0] memory_din_cpu;
    wire memory_read_ppu;
    reg [7:0] memory_din_ppu;
    wire memory_write;
    wire [7:0] memory_dout;
    wire [8:0] cycle;
    wire [8:0] scanline;
    wire [31:0] dbgadr;
    wire [1:0] dbgctr;

    // Instantiate the NES module
    NES nes (
        .clk(clk),
        .reset(reset),
        .ce(ce),
        .mapper_flags(mapper_flags),
        .sample(sample),
        .color(color),
        .joypad_strobe(joypad_strobe),
        .joypad_clock(joypad_clock),
        .joypad_data(joypad_data),
        .audio_channels(audio_channels),
        .memory_addr(memory_addr),
        .memory_read_cpu(memory_read_cpu),
        .memory_din_cpu(memory_din_cpu),
        .memory_read_ppu(memory_read_ppu),
        .memory_din_ppu(memory_din_ppu),
        .memory_write(memory_write),
        .memory_dout(memory_dout),
        .cycle(cycle),
        .scanline(scanline),
        .dbgadr(dbgadr),
        .dbgctr(dbgctr)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Testbench procedure
    initial begin
        // Open waveform file
        $dumpfile("nes.vcd");
        $dumpvars(0, nes_tb);

        // Initialize signals
        reset = 1;
        ce = 0;
        mapper_flags = 0;
        joypad_data = 0;
        audio_channels = 0;
        memory_din_cpu = 0;
        memory_din_ppu = 0;

        // Reset pulse
        #10 reset = 0;

        // Apply test stimulus
        #20 ce = 1;
        mapper_flags = 32'h12345678;  // Example mapper flags
        joypad_data = 2'b10;          // Example joypad data
        audio_channels = 5'b11111;    // Enable all audio channels

        // Simulate some memory operations
        memory_din_cpu = 8'hAA;       // Example CPU memory data
        memory_din_ppu = 8'hBB;       // Example PPU memory data

        // Run simulation for a sufficient period
        #1000000;
        $writememh("frame_buffer.hex", frame_buffer); // Write pixel data to file
        $finish;
    end

    // Capture pixel data
    reg [7:0] frame_buffer [0:256*240-1]; // Example for 256x240 resolution
    always @(posedge clk) begin
        if (ce) begin
            if (scanline < 240 && cycle < 256) begin
                frame_buffer[scanline * 256 + cycle] <= color; // Capture pixel data
            end
        end
    end

endmodule
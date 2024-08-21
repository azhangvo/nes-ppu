module nes_tb (
    input wire        write_enable,
    input wire [31:0] cycle_count,

    input wire clk,
    input wire reset,
    input wire ce,

    input wire [31:0] mapper_flags,
    input wire [7:0]  memory_din_cpu,
    input wire [7:0]  memory_din_ppu,

    input logic [7:0] joypad_data1,
    input logic [7:0] joypad_data2,

    output logic [1:0]  vga_luma,
    output logic [3:0]  vga_hue,
    output logic [8:0]  vga_cycle,
    output logic [8:0]  vga_scanline,

    output logic [21:0] memory_addr,
    output logic        memory_read_cpu,
    output logic        memory_read_ppu,
    output logic        memory_write,
    output logic [7:0]  memory_dout
);
    wire [15:0] sample;
    wire [5:0]  color;
    wire        joypad_strobe;
    wire [1:0]  joypad_clock;
    // reg  [1:0]  joypad_data = 0;
    reg  [4:0]  audio_channels;
    wire [8:0]  cycle;
    wire [8:0]  scanline;
    wire [31:0] dbgadr;
    wire [1:0]  dbgctr;

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
        .joypad_data({joypad_bits2[0], joypad_bits[0]}),
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

    reg [1:0] last_joypad_clock;
    reg [7:0] joypad_bits, joypad_bits2;

    always @(posedge clk) begin
        if (joypad_strobe) begin
            joypad_bits <= joypad_data1;
            joypad_bits2 <= joypad_data2;
        end
        if (!joypad_clock[0] && last_joypad_clock[0]) begin
            // if (joypad_bits != 0) $display("%b\n", joypad_bits);
            joypad_bits <= {1'b0, joypad_bits[7:1]};
        end
        if (!joypad_clock[1] && last_joypad_clock[1])
            joypad_bits2 <= {1'b0, joypad_bits2[7:1]};
        last_joypad_clock <= joypad_clock;
    end

    // Testbench procedure
    initial begin
        // Initialize signals
        // mapper_flags    = 0;
        // joypad_data     = 0;
        // audio_channels  = 0;
        // memory_din_cpu  = 0;
        // memory_din_ppu  = 0;

        // mapper_flags    = 32'h12345678;  // Example mapper flags
        // joypad_data     = 2'b10;         // Example joypad data
        audio_channels  = 5'b11111;      // Enable all audio channels

        // // Simulate some memory operations
        // memory_din_cpu = 8'hAA;       // Example CPU memory data
        // memory_din_ppu = 8'hBB;       // Example PPU memory data
    end

    // Capture pixel data
    reg [7:0] frame_buffer [0:256*240-1]; // Example for 256x240 resolution
    always @(posedge clk) begin
        if (ce) begin
            // if (scanline < 240 && cycle < 256) begin
            //     frame_buffer[scanline * 256 + cycle] <= {2'b00, color}; // Capture pixel data
            // end
            vga_scanline = scanline;
            vga_cycle = cycle;
            vga_luma = color[5:4];
            vga_hue = color[3:0];

        end
    end

    always @* begin
        if (write_enable) begin
            $display("Writing frame_buffer to file");
            $writememh($sformatf("output/hex/frame_%010d.hex", cycle_count), frame_buffer); // Write pixel data to file
        end
    end

endmodule
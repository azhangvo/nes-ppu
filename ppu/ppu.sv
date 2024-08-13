module PPU(
        input clk, // clock signal, should run 3x times cpu clock signal
        input ce, // probably chip enable, should be enabled when possible
        input reset,
        output [5:0] color, // color encoded in ntsc format, is not rgb, should be pulled from palette
        input [7:0] din, // dbus in
        output [7:0] dout, // dbus out
        input [2:0] ain, // address in, seems to be 3 bits, or 8, corresponding to mmio registers
        input read, // seems to be read/write flags on register in
        input write,
        output nmi, // non maskable interrupt, should communicate that current frame is done and that cpu can touch registers, ppu enters VBLANK, bit 7 in ppuctrl controls whether this should be set or not
        output vram_r, // vram read and write flags
        output vram_w,
        output [13:0] vram_a, // vram address
        input [7:0] vram_din, // vram read data (byte)
        output [7:0] vram_dout, // vram output data (byte)
        output reg [8:0] scanline, // 0->239 in normal render window, will go larger
        output reg [8:0] cycle, // 0->256 in normal render window, will go larger
        output [19:0] mapper_ppu_flags
    );
    
    reg [7:0] ppuctrl;
    reg is_even;

    wire is_end_of_scanline;
    wire is_end_of_frame;

    assign is_end_of_scanline = (!is_even && scanline == 9'b111111111) ? cycle == 340 : cycle == 341;
    assign is_end_of_frame = is_end_of_scanline && scanline == 260;

    always @ (posedge clk) begin
        if(reset) begin
            scanline <= 0;
            cycle <= 0;
            is_even <= 0;
        end
        else if(ce) begin
            scanline <= !is_end_of_scanline ? scanline      :
                        is_end_of_frame     ? -1            :
                                              scanline + 1;
            cycle <= is_end_of_scanline ? 0 : cycle + 1;
            is_even <= is_end_of_frame ? !is_even : is_even;
        end
    end

endmodule
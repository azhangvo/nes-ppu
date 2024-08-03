module PPU(
        input clk, 
        input ce, 
        input reset,
        output [5:0] color,
        input [7:0] din,
        output [7:0] dout,
        input [2:0] ain,
        input read,
        input write,
        output nmi,
        output vram_r,
        output vram_w,
        output [13:0] vram_a,
        input [7:0] vram_din,
        output [7:0] vram_dout,
        output [8:0] scanline,
        output [8:0] cycle,
        output [19:0] mapper_ppu_flags
    );
    
    

endmodule
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
    
    reg [7:0] PPUCTRL;
    // Bit 1 & 0 - 00 = 2000, 01 = 2400, 10 = 2800, 11 = 2C00
    // Bit construct 0010bb00xxxxxxxx
    // Bit construct 0010bbhhhhhwwwww
    reg [7:0]  PPUMASK;
    reg [6:0]  PPUSTATUS;
    reg [7:0]  OAMADDR;
    reg [7:0]  OAMDATA;
    reg [7:0]  PPUSCROLL;
    reg [15:0] PPUADDR;
    reg [7:0]  PPUDATA;
    reg        w;
    reg        nmi_active;

    reg [7:0]  ldout;

    reg [7:0] cam_position_x;
    reg [7:0] cam_position_y;
    reg [7:0] cam_offset_x;
    reg [7:0] cam_offset_y;

    reg is_even; // Keep track of if the current frame is even or not

    wire is_end_of_scanline; // End of scanline usually occurs on cycle 341, but happens on cycle 340 for special idle scanline 261 (or -1) if the frame is odd
    wire is_end_of_frame; // 260 is the last scanline, end of frame happens when we are on the last scanline and at its end.
    wire is_in_vblank;
    wire is_entering_vblank; // We should enter vblank on scanline 240
    wire is_exiting_vblank; // We should exit vblank after scanline 260, or on scanline 261 (-1)
    wire is_signaling_cpu; // We should signal the CPU with vblank flag and nmi on tick 1 (second tick) of scanline 240. 
    wire is_in_background_stage;
    wire [2:0] background_stage; // represent what stage in background fetch we are in
                                 // 001/010 - nametable byte
                                 // 011/100 - attribute table byte
                                 // 101/110 - pattern table tile low
                                 // 111/000 - pattern table tile high

    initial begin
        w = 0;
        PPUCTRL = 0;
        PPUDATA = 0;
        PPUADDR = 0;
    end

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
                                              scanline + 1  ;

            cycle <= is_end_of_scanline ? 0 : cycle + 1;
            is_even <= is_end_of_frame ? !is_even : is_even;

            if(is_end_of_scanline && scanline == 240)
                nmi_active <= 1;
            if(is_end_of_frame)
                nmi_active <= 0;

            // $display("%d %d %d", cycle, is_in_background_stage, background_stage);
        end
    end

    assign nmi = nmi_active && PPUCTRL[7];
                                 
    always @ (posedge clk) begin
        if (ain == 0 && write) begin
            // $display("writing to ppuctrl");
            PPUCTRL <= din;
        end
        if (ain == 2 && read) begin
            // $display("reading ppustatus");
            ldout = {nmi_active, PPUSTATUS};
            w <= 0;
        end
        if (ain == 6 && write) begin
            $display("saving address %d %x", w, din);
            if(!w)
                PPUADDR[15:8] <= din;
            else
                PPUADDR[7:0] <= din;
            w <= !w;
        end
        if (ain == 7 && (write || read)) begin
            PPUADDR <= PPUADDR + (PPUCTRL[2] ? 32 : 1);
            // $display("trying to write to data");
        end
    end

    assign dout = ldout;

    assign is_in_background_stage = cycle >= 1 && cycle <= 256;
    wire [8:0] background_stage_cycle;
    assign background_stage_cycle = cycle - 1;
    assign background_stage = background_stage_cycle[2:0];
    wire [4:0] next_cam_offset_x;
    wire [4:0] next_cam_offset_y;
    assign next_cam_offset_x = background_stage_cycle[7:3] + 5'b10;
    assign next_cam_offset_y = scanline[7:3];

    // We want to start loading tile 3 on tick 1
    // Bit construct 0010bbhhhhhwwwww
    assign vram_a = 
            ain == 7 && (write || read)  ?  PPUADDR[13:0]  :
            background_stage[2:1] == 0  ?  {2'b10, PPUCTRL[1:0], next_cam_offset_y, next_cam_offset_x}  :
            14'b0;

    assign vram_r =
            ain == 7 && read  ?  1  :
            background_stage[2:1] == 0  ?  1  :
            0;

    assign vram_w =
            ain == 7 && write  ?  1  :
            0;

    always @ (posedge clk) begin
        // if (vram_w) begin
        //     $display("writing, addr %x %x %x", PPUADDR, PPUADDR[13:0], vram_a);
        // end
        // if (vram_r) begin
        //     $display("nametable %d scanline %d cycle %d", PPUCTRL[2], scanline, cycle);
        //     $display("reading addr %x -> value %x", vram_a, vram_din);
        // end
    end

endmodule
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
    reg [15:0] PPUSCROLL;
    reg [15:0] PPUADDR;
    reg [7:0]  PPUDATA;
    reg        w;
    reg        is_in_vblank;

    reg [4:0] coarse_scroll_x;
    reg [7:0] scroll_y;

    reg [7:0] ldout;

    reg [7:0] bg_nametable_addr;

    wire [7:0] cam_position_x;
    wire [7:0] cam_position_y;
    reg [7:0] cam_offset_x;
    reg [7:0] cam_offset_y;

    reg is_even; // Keep track of if the current frame is even or not

    wire is_end_of_scanline; // End of scanline usually occurs on cycle 341, but happens on cycle 340 for special idle scanline 261 (or -1) if the frame is odd
    wire is_end_of_frame; // 260 is the last scanline, end of frame happens when we are on the last scanline and at its end.
    wire is_entering_vblank; // We should enter vblank on scanline 240
    wire is_exiting_vblank; // We should exit vblank after scanline 260, or on scanline 261 (-1)
    wire is_signaling_cpu; // We should signal the CPU with vblank flag and nmi on tick 1 (second tick) of scanline 240. 
    wire is_in_background_stage;
    wire [2:0] background_stage; // represent what stage in background fetch we are in
                                 // 001/010 - nametable byte
                                 // 011/100 - attribute table byte
                                 // 101/110 - pattern table tile low
                                 // 111/000 - pattern table tile high

    reg [5:0] palette [0:31];
    initial begin
        $readmemh("lib/oam_palette.txt", palette);
    end

    assign vram_dout = din;

    initial begin
        w = 0;
        is_even = 1;
        PPUCTRL = 0;
        PPUDATA = 0;
        PPUADDR = 0;
    end

    assign is_end_of_scanline = (!is_even && scanline == 9'b111111111 && !is_in_vblank && PPUMASK[4:3] != 0) ? cycle == 339 : cycle == 340;
    assign is_end_of_frame = is_end_of_scanline && scanline == 260;

    always @ (posedge clk) begin
        if(reset) begin
            scanline <= 0;
            cycle <= 0;
            is_even <= 1;
            is_in_vblank <= 1;
        end
        else if(ce) begin
            scanline <= !is_end_of_scanline ? scanline      :
                        is_end_of_frame     ? 9'b111111111  :
                                              scanline + 1  ;

            cycle <= is_end_of_scanline ? 0 : cycle + 1;
            is_even <= is_end_of_frame ? !is_even : is_even;

            if(is_end_of_scanline && scanline == 240) begin
                is_in_vblank <= 1;
                // $display("activating nmi %d", PPUCTRL);
            end
            if(is_end_of_frame) begin
                is_in_vblank <= 0;
                // $display("disabling nmi %d", PPUCTRL);
            end

            // $display("%d %d %d", cycle, is_in_background_stage, background_stage);
        end
    end

    assign nmi = is_in_vblank && PPUCTRL[7];
                                 
    always @ (posedge clk) begin
        if (ce) begin
            if (ain == 0 && write) begin
                // $display("writing to ppuctrl %x", din);
                PPUCTRL <= din;
            end
            if (ain == 1 && write) begin
                // $display("writing to ppumask %x", din);
                PPUMASK <= din;
            end
            if (ain == 2 && read) begin
                is_in_vblank <= 0;
                w <= 0;
            end
            if (ain == 5 && write) begin
                if(!w)
                    PPUSCROLL[15:8] <= din;
                else
                    PPUSCROLL[7:0] <= din;
                w <= !w;
            end
            if (ain == 6 && write) begin
                // $display("saving address %d %x cycle %d", w, din, cycle);
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
            // if (ain == )
        end
    end

    always @* begin
        if (ain == 2) begin
            ldout = {is_in_vblank, PPUSTATUS};
            // $display("reading ppustatus %x %x %x", {is_in_vblank, PPUSTATUS}, ldout, dout);
        end else begin
            ldout = 8'b0;
        end
    end

    assign cam_position_x = PPUSCROLL[15:8];
    assign cam_position_y = PPUSCROLL[7:0];

    assign dout = ldout;

    assign is_in_background_stage = cycle >= 1 && cycle <= 256;
    wire [8:0] background_stage_cycle;
    assign background_stage_cycle = cycle - 1;
    assign background_stage = background_stage_cycle[2:0];

    always @ (posedge clk) begin
        if (ce && !is_in_vblank && scanline != 240 && PPUMASK[4:3] != 0) begin
            if (cycle[2:0] == 3 && ((cycle >= 1 && cycle < 256) || (cycle >= 320 && cycle < 336))) begin
                coarse_scroll_x <= coarse_scroll_x + 1;
                // $display("increment %d %d %x", scanline, cycle, coarse_scroll_x);
                // TODO: deal with nametable rollover
            end

            if (cycle == 251) begin
                scroll_y <= scroll_y + 1;
                // TODO: deal with nametable rollover
            end

            if (cycle == 320) begin
                coarse_scroll_x <= PPUSCROLL[15:11];
            end

            if (scanline == 9'b111111111 && cycle == 319) begin // load starting scroll positions into internal registers before cycle 320 of scanline -1
                coarse_scroll_x <= PPUSCROLL[15:11];
                // $display("reset %x", PPUSCROLL[15:8]);
                scroll_y <= PPUSCROLL[7:0];
            end
        end
    end

    // We want to start loading tile 3 on tick 1
    // Bit construct 0010bbhhhhhwwwww
    assign vram_a = 
            ain == 7 && (write || read)  ?  PPUADDR[13:0]                                                      :
            background_stage[2:1] == 0   ?  {2'b10, PPUCTRL[1:0], scroll_y[7:3], coarse_scroll_x}                :
            background_stage[2:1] == 1   ?  {2'b10, PPUCTRL[1:0], 2'b11, 2'b11, scroll_y[7:5], coarse_scroll_x[4:2]}  :
            background_stage[2:1] == 2   ?  {1'b0, PPUCTRL[4], bg_nametable_addr, 1'b0, scroll_y[2:0]}         :
            background_stage[2:1] == 3   ?  {1'b0, PPUCTRL[4], bg_nametable_addr, 1'b1, scroll_y[2:0]}         :
            14'b0;

    assign vram_r =
            ain == 7 && read  ?  1  :
            (cycle[0] == 1 && !(is_in_vblank || scanline == 240) && (PPUMASK[4:3] != 0))  ?  1  :
            0;

    assign vram_w =
            ain == 7 && write  ?  1  :
            0;

    reg  [7:0]  bg_palette_latch_1;
    reg  [1:0]  bg_attrib_latch;
    reg  [15:0] bg_palette_shift_reg_1;
    reg  [15:0] bg_palette_shift_reg_2;
    reg  [7:0]  bg_attrib_shift_reg_1;
    reg  [7:0]  bg_attrib_shift_reg_2;
    wire [3:0]  bg_pixel;

    always @ (posedge clk) begin
        // if (ce && !is_in_vblank && scanline != 240 && PPUMASK[4:3] != 0) begin
        if (cycle < 336) begin
            bg_palette_shift_reg_1[14:0] <= bg_palette_shift_reg_1[15:1];
            bg_palette_shift_reg_2[14:0] <= bg_palette_shift_reg_2[15:1];
            bg_attrib_shift_reg_1[6:0] <= bg_attrib_shift_reg_1[7:1];
            bg_attrib_shift_reg_2[6:0] <= bg_attrib_shift_reg_2[7:1];
            if (cycle[2:0] == 1) begin
                // Name table used for pattern table access
                bg_nametable_addr <= vram_din;
            end
            if(cycle[2:0] == 4) begin
                // Attribute table
                bg_attrib_latch <= vram_din[{scroll_y[3], coarse_scroll_x[0], 1'b0} +: 2];
            end
            if(cycle[2:0] == 6) begin
                // Pattern table #0
                bg_palette_latch_1 <= vram_din;
            end
            if(cycle[2:0] == 0) begin
                // Pattern table #1
                // {<<8{array}}
                // bg_palette_shift_reg_2[15:8] <= vram_din;
                // bg_palette_shift_reg_1[15:8] <= bg_palette_latch_1;
                // bg_attrib_shift_reg_1[7] <= bg_attrib_latch[0];
                // bg_attrib_shift_reg_2[7] <= bg_attrib_latch[1];
                bg_palette_shift_reg_2[15:8] <= {<<{vram_din}};
                bg_palette_shift_reg_1[15:8] <= {<<{bg_palette_latch_1}};
                bg_attrib_shift_reg_1[7] <= bg_attrib_latch[0];
                bg_attrib_shift_reg_2[7] <= bg_attrib_latch[1];
            end
        end
    end

    assign bg_pixel = {bg_attrib_shift_reg_2[0], bg_attrib_shift_reg_1[0], bg_palette_shift_reg_2[0], bg_palette_shift_reg_1[0]}; // TODO implement fine x

    assign color = palette[{1'b0, bg_pixel}]; // TODO implement obj

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
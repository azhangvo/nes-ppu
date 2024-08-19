module Sprite #(parameter INDEX=0) (
        input        clk,
        input  [8:0] scanline,
        input  [8:0] cycle,
        input  [4:0] coarse_scroll_x,
        input  [2:0] fine_scroll_x,
        input  [7:0] sprite_data [3:0],
        input  [7:0] din,
        output [7:0] nametable,
        output [2:0] local_y_scroll,
        output [4:0] pixel
    );

    // byte 0 represents y offset
    // byte 1 is sprite tile number
    // byte 2 is sprite attribute
    // byte 3 represents x offset

    assign local_y_scroll = sprite_data[2][7] ? sprite_data[0][2:0] - scanline[2:0] : scanline[2:0] - sprite_data[0][2:0];
    assign nametable = sprite_data[1];

    reg [7:0] pattern1;
    reg [7:0] pattern2;
    reg [7:0] offset_x;
    reg [7:0] offset_y;
    reg [7:0] attrib;
    wire [2:0] index = INDEX;
    wire [3:0] next_index = INDEX + 1;

    always @ (posedge clk) begin
        if (cycle == {3'b100, index, 3'b110}) begin
            pattern1 <= sprite_data[2][6] ? din : {<<{din}};
            // if (index == 0)
            //     $display("saving %d %x %b", cycle, nametable, din);
        end
        if (cycle == {2'b10, next_index, 3'b000}) begin // Dont know if i can get away with this
            pattern2 <= sprite_data[2][6] ? din : {<<{din}};
            offset_x <= sprite_data[3];
            offset_y <= sprite_data[0];
            attrib <= sprite_data[2];
            // $display("saving 2 %d %d", index, cycle);
        end
        // if (index == 0 && cycle == 0 && sprite_enabled) begin
        //     $display("%d %d %x", scanline, cycle, nametable);
        // end
    end

    wire sprite_enabled = offset_y != 0 || offset_x != 0 || attrib != 0;
    // wire sprite_enabled = 1;

    // wire [7:0] scroll_x = {coarse_scroll_x, fine_scroll_x};
    wire [8:0] scroll_x = cycle - 1;
    wire [7:0] local_x_index = scroll_x[7:0] - offset_x;
    wire [2:0] local_fine_x_index = local_x_index[2:0];
    wire enabled = (scroll_x[7:0] >= offset_x && scroll_x[7:0] < offset_x + 8 && cycle >= 1 && cycle < 256) ? 1 : 0;

    wire visible = sprite_enabled && enabled && !sprite_data[2][5] && (pattern2[local_fine_x_index] != 0 || pattern1[local_fine_x_index] != 0);

    // assign pixel = {visible, attrib[0], attrib[1], pattern2[local_fine_x_index], pattern1[local_fine_x_index]};
    assign pixel = {visible, attrib[1], attrib[0], pattern2[local_fine_x_index], pattern1[local_fine_x_index]};
    // assign pixel = {visible, 4'b0110};
    // assign pixel = {sprite_enabled && enabled, sprite_data[2][0], sprite_data[2][1], 2'b10};

    // always @ (posedge clk) begin
    //     if (index == 7 && enabled && sprite_enabled) begin
    //         $display("%d %d %d %d %d", visible, scroll_x, local_fine_x_index, sprite_data[3], cycle);
    //     end
    // end

endmodule // Sprite

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
    reg [2:0] fine_scroll_x;
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

    reg [7:0] oam [255:0];
    reg [7:0] sprite_oam [7:0][3:0];
    reg oam_enable;
    reg [5:0] sprite_index;

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
            if (ain == 3 && write) begin
                OAMADDR <= din;
            end
            if (ain == 4 && write) begin
                oam[OAMADDR] <= din;
                OAMADDR <= OAMADDR + 1;
            end
            if (ain == 4 && read) begin
                ldout = oam[OAMADDR];
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
                if(PPUADDR[13:8] == 6'b111111) begin
                    if (!(PPUADDR[3:2] != 0 && PPUADDR[1:0] == 0))
                        palette[PPUADDR[4:0]] <= din[5:0];
                end
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
            if ((cycle >= 1 && cycle < 256) || (cycle >= 320 && cycle < 336)) begin
                fine_scroll_x <= fine_scroll_x + 1;
                // $display("increment %d %d %x", scanline, cycle, coarse_scroll_x);
                // TODO: deal with nametable rollover
            end

            if (cycle == 251) begin
                scroll_y <= scroll_y + 1;
                // TODO: deal with nametable rollover
            end

            if (cycle >= 257 && cycle < 320) begin
                OAMADDR <= 0;
            end

            if (cycle == 320) begin
                coarse_scroll_x <= PPUSCROLL[15:11];
                fine_scroll_x <= PPUSCROLL[10:8];
            end

            if (scanline == 9'b111111111 && cycle == 319) begin // load starting scroll positions into internal registers before cycle 320 of scanline -1
                coarse_scroll_x <= PPUSCROLL[15:11];
                fine_scroll_x <= PPUSCROLL[10:8];
                // $display("reset %x", PPUSCROLL[15:8]);
                scroll_y <= PPUSCROLL[7:0];
            end
        end
    end

    wire [7:0] sprite_nametable_list [7:0];
    wire [2:0] sprite_scroll_y_list  [7:0];
    wire [4:0] sprite_pixel_list     [7:0];

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin
            Sprite #(.INDEX(i)) sprite (clk, scanline, cycle, coarse_scroll_x, fine_scroll_x, sprite_oam[i], vram_din, sprite_nametable_list[i], sprite_scroll_y_list[i], sprite_pixel_list[i]);
        end
    endgenerate

    wire [7:0] sprite_nametable_address = sprite_nametable_list[cycle[5:3]];
    wire [2:0] sprite_scroll_y = sprite_scroll_y_list[cycle[5:3]];
    wire [4:0] sprite_pixel = 
            sprite_pixel_list[0][4] ? sprite_pixel_list[0] :
            sprite_pixel_list[1][4] ? sprite_pixel_list[1] :
            sprite_pixel_list[2][4] ? sprite_pixel_list[2] :
            sprite_pixel_list[3][4] ? sprite_pixel_list[3] :
            sprite_pixel_list[4][4] ? sprite_pixel_list[4] :
            sprite_pixel_list[5][4] ? sprite_pixel_list[5] :
            sprite_pixel_list[6][4] ? sprite_pixel_list[6] :
            sprite_pixel_list[7][4] ? sprite_pixel_list[7] : sprite_pixel_list[0];


    // We want to start loading tile 3 on tick 1
    // Bit construct 0010bbhhhhhwwwww
    assign vram_a = 
            ain == 7 && (write || read)  ?  PPUADDR[13:0]                                                      :
            background_stage[2:1] == 0   ?  {2'b10, PPUCTRL[1:0], scroll_y[7:3], coarse_scroll_x}                :
            background_stage[2:1] == 1   ?  {2'b10, PPUCTRL[1:0], 2'b11, 2'b11, scroll_y[7:5], coarse_scroll_x[4:2]}  :
            background_stage[2:1] == 2   ?  {1'b0, cycle >= 256 && cycle < 320 ? PPUCTRL[3] : PPUCTRL[4], cycle >= 256 && cycle < 320 ? sprite_nametable_address : bg_nametable_addr, 1'b0, cycle >= 256 && cycle < 320 ? sprite_scroll_y : scroll_y[2:0]}         :
            background_stage[2:1] == 3   ?  {1'b0, cycle >= 256 && cycle < 320 ? PPUCTRL[3] : PPUCTRL[4], cycle >= 256 && cycle < 320 ? sprite_nametable_address : bg_nametable_addr, 1'b1, cycle >= 256 && cycle < 320 ? sprite_scroll_y : scroll_y[2:0]}         :
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
            if (cycle[2:0] == 2) begin
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

    reg [1:0] oam_write_status;
    reg [2:0] secondary_sprite_index;

    always @ (posedge clk) begin
        if (cycle <= 64) begin
            sprite_oam[cycle[5:3]][cycle[2:1]] <= 0;
        end
        if (cycle == 64) begin
            oam_enable <= 1;
            oam_write_status <= 0;
            sprite_index <= 0;
            secondary_sprite_index <= 0;
        end
        if (cycle >= 65 && cycle <= 256 && cycle[0] == 0) begin
            case (oam_write_status)
            0: begin
                if (scroll_y >= oam[{sprite_index, 2'b00}] && scroll_y < oam[{sprite_index, 2'b00}] + 8) begin // check y coordinate, TODO assuming 8x8
                    if(oam_enable) begin
                        oam_write_status <= 1;
                        sprite_oam[secondary_sprite_index][0] <= oam[{sprite_index, 2'b00}];
                    end else begin
                        // TODO overflow
                    end
                end else begin
                    sprite_index <= sprite_index + 1;
                    if(sprite_index == 63) begin
                        oam_enable <= 0;
                    end
                end
            end
            1: begin
                oam_write_status <= 2;
                sprite_oam[secondary_sprite_index][1] <= oam[{sprite_index, 2'b01}];
            end
            2: begin
                oam_write_status <= 3;
                sprite_oam[secondary_sprite_index][2] <= oam[{sprite_index, 2'b10}];
            end
            3: begin
                oam_write_status <= 0;
                secondary_sprite_index <= secondary_sprite_index + 1;
                sprite_index <= sprite_index + 1;
                sprite_oam[secondary_sprite_index][3] <= oam[{sprite_index, 2'b11}];
                if (secondary_sprite_index == 7) begin
                    oam_enable <= 0;
                end
            end
            endcase
        end
    end

    assign bg_pixel = {bg_attrib_shift_reg_2[0], bg_attrib_shift_reg_1[0], bg_palette_shift_reg_2[0], bg_palette_shift_reg_1[0]}; // TODO implement fine x
    // assign bg_pixel = {bg_attrib_shift_reg_1[0], bg_attrib_shift_reg_2[0], bg_palette_shift_reg_2[0], bg_palette_shift_reg_1[0]}; // TODO implement fine x
    // assign bg_pixel = {bg_attrib_shift_reg_2[0], bg_attrib_shift_reg_1[0], bg_palette_shift_reg_1[0], bg_palette_shift_reg_2[0]}; // TODO implement fine x

    wire [4:0] pixel = sprite_pixel[4] ? sprite_pixel : {1'b0, bg_pixel};
    assign color = palette[pixel]; // TODO implement obj

    always @ (posedge clk) begin
        // if (cycle == {3'b100, 3'b0, 3'b101} || cycle == {3'b100, 3'b0, 3'b110}) begin
        //     $display("%x %d %x", vram_a, vram_r, din);
        // end
        // if (ce && bg_pixel != 0) begin
        //     $display("%d pixel %x %x", scanline, bg_pixel, color);
        // end
        // if (vram_w) begin
        //     $display("writing, addr %x %x %x", PPUADDR, PPUADDR[13:0], vram_a);
        // end
        // if (vram_r) begin
        //     $display("nametable %d scanline %d cycle %d", PPUCTRL[2], scanline, cycle);
        //     $display("reading addr %x -> value %x", vram_a, vram_din);
        // end
    end

endmodule
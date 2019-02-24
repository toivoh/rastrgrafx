`timescale 1ns / 1ps
`include "common.svh"
`include "hdmi.svh"


module main #(parameter PIXEL_WIDTH = 8, parameter ADDR_WIDTH = 18, DATA_WIDTH = 32, X_BITS = 11, Y_BITS = 10, SCALE_BITS = 4, VRAM_ADDR_WIDTH = 14, DEBUG_GFX_MODE = 0) (
        input clk,
        input aresetn,

        output RGB24sync rgb24sync,

        output new_frame,

        // Write_interface
        input s_valid,
        input [ADDR_WIDTH-1:0] s_addr,
        input [DATA_WIDTH-1:0] s_data,
        output s_ready
    );
    localparam ModeLine graphics_mode = DEBUG_GFX_MODE ? mode_70x70_fake : mode_1280x1024_60;

    localparam VRAM_DATA_WIDTH = 8;
    localparam TILEMAP_ADDR_WIDTH = 13;

    localparam NUM_REGS = 8;
    
    localparam SPRITE_REG_ADDR_BITS = 8;

    localparam TILEMAP_BASE = 2**VRAM_ADDR_WIDTH;
    localparam TILEMAP2_BASE = TILEMAP_BASE + 2**TILEMAP_ADDR_WIDTH;
    localparam PAL_BASE = TILEMAP2_BASE + 2**TILEMAP_ADDR_WIDTH;
    localparam SPRITE_REG_BASE = PAL_BASE + 256; 
    localparam REG_BASE = SPRITE_REG_BASE + 256;


    localparam SPRITE_BUFFER_WIDTH_BITS = 6; // in bytes
    localparam SPRITE_WIDTH_BITS = SPRITE_BUFFER_WIDTH_BITS; // in pixels

    reg [31:0] registers[NUM_REGS];
    
    initial begin
        for (int i=0; i < NUM_REGS; i++) registers[i] = 0;
        registers[4] = 3; // bpp_log2
    end

    wire [X_BITS-1:0] x_offset = registers[0];
    wire [Y_BITS-1:0] y_offset = registers[1];
    
    wire [SCALE_BITS-1:0] x_shift = registers[2];
    wire [SCALE_BITS-1:0] y_shift = registers[3];
    
    wire [1:0] bpp_log2 = registers[4];


    (* ram_style = "block" *) reg [VRAM_DATA_WIDTH-1:0] vram[0:2**VRAM_ADDR_WIDTH - 1];

    initial begin
        for (int k = 0; k < 256; k++) begin
            for (int y = 0; y < 8; y++) begin
                for (int x = 0; x < 8; x++) begin
                    vram[x + 8*(y + 8*k)] = x ^ (y << 3) ^ k;
                end
            end
        end
    end
    
    (* ram_style = "block" *) reg [7:0] tilemap[0:2**TILEMAP_ADDR_WIDTH - 1];
    (* ram_style = "block" *) reg [7:0] tilemap2[0:2**TILEMAP_ADDR_WIDTH - 1];

    initial begin
        for (int k = 0; k < 2**TILEMAP_ADDR_WIDTH; k++) begin
            tilemap[k] = k ^ (k >> 7);
            tilemap2[k] = k + (k >> 7);
        end
    end

    (* ram_style = "block" *) reg [31:0] palette[256];
    initial begin
        for (int i=0; i < 256; i++) begin
            automatic logic [7:0] r = i[7:5] << 5;
            automatic logic [7:0] g = i[4:2] << 5;
            automatic logic [7:0] b = i[1:0] << 6;
            palette[i] = {r,g,b};
        end
    end


    // Bus interface
    wire [ADDR_WIDTH-3:0] write_addr = s_addr >> 2;

    assign s_ready = 1;
    // 32 bit writes map to writing just one vram / tilemap entry
    always @(posedge clk) if (s_valid) begin
        if      (write_addr < TILEMAP_BASE)    vram[write_addr] <= s_data;
        else if (write_addr < TILEMAP2_BASE)   tilemap[write_addr   - TILEMAP_BASE] <= s_data;
        else if (write_addr < PAL_BASE)        tilemap2[write_addr  - TILEMAP2_BASE] <= s_data;
        else if (write_addr < SPRITE_REG_BASE) palette[write_addr   - PAL_BASE] <= s_data;
        else if (write_addr < REG_BASE);
        else                                   registers[write_addr - REG_BASE] <= s_data;
    end
    WriteChannel #(.ADDR_SIZE(SPRITE_REG_ADDR_BITS), .DATA_WIDTH(32)) sprite_reg_write();
    assign sprite_reg_write.enable = s_valid && ((SPRITE_REG_BASE <= write_addr) && (write_addr < REG_BASE));
    assign sprite_reg_write.addr = write_addr - SPRITE_REG_BASE;
    assign sprite_reg_write.data = s_data;

    // Pixel processing
    // ----------------

    ReadChannel #(.ADDR_SIZE(VRAM_ADDR_WIDTH)) vram_read();
    ReadChannel #(.ADDR_SIZE(VRAM_ADDR_WIDTH)) sprite_vram_read();

    assign sprite_vram_read.data = vram_read.data;
    always @(posedge clk) begin
        if (sprite_vram_read.enable || vram_read.enable) vram_read.data <= vram[sprite_vram_read.enable ? sprite_vram_read.addr : vram_read.addr];
    end

    localparam NUM_STAGES = 4;

    PixelState pstates[NUM_STAGES]; 
    always @(posedge clk) pstates[1:NUM_STAGES-1] <= pstates[0:NUM_STAGES-2];

    wire hblank_start; // Delayed by NUM_STAGES cycles, to be sure we don't start the sprite row transfers too soon
    wire [X_BITS-1:0] x;
    wire [Y_BITS-1:0] y;
    raster_scan #(.COORD_BITS(X_BITS), .HBLANK_START_REPORT_DELAY(NUM_STAGES)) raster_scan_inst(
        .clk(clk), .mode(graphics_mode), .state(pstates[0]), .x(x), .y(y), .new_frame(new_frame), .hblank_start(hblank_start)
     );

    // ## Tile map

    ReadChannel #(.ADDR_SIZE(TILEMAP_ADDR_WIDTH)) tilemap_read();
    ReadChannel #(.ADDR_SIZE(TILEMAP_ADDR_WIDTH)) tilemap2_read();

    always @(posedge clk) begin
        if (tilemap_read.enable) tilemap_read.data <= tilemap[tilemap_read.addr];
        if (tilemap2_read.enable) tilemap2_read.data <= tilemap2[tilemap2_read.addr];
    end

    wire [PIXEL_WIDTH-1:0] bkg_pixel;

    tilemap_renderer #(.X_BITS(X_BITS), .Y_BITS(Y_BITS), .TILE_ADDR_X_BITS(7), .TILE_ADDR_Y_BITS(6), .PIXEL_BITS(PIXEL_WIDTH)) bkg(
        .clk(clk),
        .bpp_log2(bpp_log2),
        .x_shift(x_shift), .y_shift(y_shift),
        .x_in(x + x_offset), .y_in(y + y_offset),
        .pixel(bkg_pixel),
        .tilemap_read(tilemap_read), .tilemap2_read(tilemap2_read), .pixel_read(vram_read)
    ); 

    // Sprites
    // -------
    wire start_sprites_transfer = hblank_start;
    wire [PIXEL_WIDTH-1:0] sprite_pixel;

    sprite_renderer #(.X_BITS(X_BITS), .Y_BITS(Y_BITS), .WIDTH_BITS(SPRITE_WIDTH_BITS), .PIXEL_BITS(PIXEL_WIDTH), .PITCH_L2_BITS(3),
                      .VRAM_ADDR_BITS(VRAM_ADDR_WIDTH), .BUFFER_ADDR_BITS(SPRITE_BUFFER_WIDTH_BITS), .SPRITE_WIDTH_BITS(SPRITE_WIDTH_BITS)) sprites(
        .clk(clk),
        .x_in(x), .y_in(y),
        .start_sprites_transfer(start_sprites_transfer),
        .pixel(sprite_pixel),
        .reg_write(sprite_reg_write), .vram_read(sprite_vram_read)
    );

    // ## Pixel mixer

    wire [PIXEL_WIDTH-1:0] pixel = (sprite_pixel == 0) ? bkg_pixel : sprite_pixel;

    // ## Palette

    RGB24 rgb;
    reg [23:0] pixel_rgb;
    always @(posedge clk) pixel_rgb <= palette[pixel];
    assign rgb24sync.r = pixel_rgb[16 +: 8];
    assign rgb24sync.g = pixel_rgb[ 8 +: 8];
    assign rgb24sync.b = pixel_rgb[ 0 +: 8];

    // ## Output

    wire PixelState pstate_out = pstates[NUM_STAGES-1];
    assign rgb24sync.hsync = pstate_out.hsync;
    assign rgb24sync.vsync = pstate_out.vsync;
    assign rgb24sync.draw  = pstate_out.draw;
    assign rgb24sync.wren  = 1;
endmodule

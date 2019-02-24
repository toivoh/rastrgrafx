`timescale 1ns / 1ps
`include "common.svh"


module tilemap_renderer #(parameter X_BITS = 10, Y_BITS = 9, TILE_ADDR_X_BITS = 6, TILE_ADDR_Y_BITS = 5, TILE_INDEX_BITS = 8, PIXEL_OFFSET_X_BITS = 3, PIXEL_OFFSET_Y_BITS = 3, PIXEL_BITS = 8, SCALE_BITS = 2) (
        input clk,

        input [SCALE_BITS-1:0] x_shift, y_shift,
        input [1:0] bpp_log2,

        input [X_BITS-1:0] x_in,
        input [Y_BITS-1:0] y_in,

        ReadChannel.Master tilemap_read,
        ReadChannel.Master tilemap2_read,
        ReadChannel.Master pixel_read,

        output [PIXEL_BITS-1:0] pixel
    );

    localparam TILE_ADDR_BITS = TILE_ADDR_X_BITS + TILE_ADDR_Y_BITS; 
    localparam PIXEL_ADDR_BITS = TILE_INDEX_BITS + PIXEL_OFFSET_X_BITS + PIXEL_OFFSET_Y_BITS;

    // Stage 0

    wire [X_BITS-1:0] x = x_in >> x_shift;
    wire [Y_BITS-1:0] y = y_in >> y_shift;

    wire [TILE_ADDR_X_BITS-1:0] tile_x = x[PIXEL_OFFSET_X_BITS +: TILE_ADDR_X_BITS];
    wire [TILE_ADDR_Y_BITS-1:0] tile_y = y[PIXEL_OFFSET_Y_BITS +: TILE_ADDR_Y_BITS];

    wire [TILE_ADDR_BITS-1:0] tile_addr = {tile_y, tile_x};

    assign tilemap_read.enable = 1;
    assign tilemap_read.addr = tile_addr; // Base address handled by slave
    wire [TILE_INDEX_BITS-1:0] tile_index = tilemap_read.data;

    assign tilemap2_read.enable = 1;
    assign tilemap2_read.addr = tile_addr; // Base address handled by slave
    wire [TILE_INDEX_BITS-1:0] tile_data = tilemap2_read.data;

    reg [PIXEL_OFFSET_X_BITS-1:0] pixel_x;
    reg [PIXEL_OFFSET_Y_BITS-1:0] pixel_y;
    
    always @(posedge clk) begin    
        pixel_x <= x[0 +: PIXEL_OFFSET_X_BITS];
        pixel_y <= y[0 +: PIXEL_OFFSET_Y_BITS];
    end

    // Stage 1
    // inputs: pixel_x, pixel_y, tile_index, tile_data

    wire [PIXEL_ADDR_BITS+3-1:0] pixel_addr = {tile_index, pixel_y, pixel_x};
    
    reg [PIXEL_ADDR_BITS+3-1:0] pixel_bit_addr;    
    always @(posedge clk) pixel_bit_addr <= pixel_addr << bpp_log2;

    // Stage 2
    // inputs: pixel_bit_addr, tile_pal0

    assign pixel_read.enable = 1;
    assign pixel_read.addr = pixel_bit_addr >> 3;

    reg [2:0] pixel_frac_addr;
    always @(posedge clk) pixel_frac_addr <= pixel_bit_addr[2:0];
    wire [PIXEL_BITS-1:0] pixel_bits = pixel_read.data;

    reg [7:0] tile_pal0, tile_pal;
    always @(posedge clk) tile_pal0 <= tile_data;
    always @(posedge clk) tile_pal <= tile_pal0;

    // Stage 3
    // inputs: pixel_bits, pixel_frac_addr, tile_pal

    assign pixel = extract_pixel(.bpp_log2(bpp_log2), .pixel_bits(pixel_bits), .bit_addr(pixel_frac_addr), .high_bits(tile_pal), .keep_0(0));
endmodule

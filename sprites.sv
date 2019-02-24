`timescale 1ns / 1ps
`include "common.svh"


module sprite_row_renderer #(parameter X_BITS = 10, WIDTH_BITS = 6, PIXEL_BITS = 8, BUFFER_ADDR_BITS = 6) (
        input clk,

        input [1:0] bpp_log2,
        input [PIXEL_BITS-1:0] pal_bits,

        input [X_BITS-1:0] x_in,
        input [WIDTH_BITS-1:0] width_minus_1,
        
        ReadChannel.Master pixel_read,
        
        output [PIXEL_BITS-1:0] pixel
    );

    // Stage 0

    wire [X_BITS-1:0] x = x_in;
    wire active = x <= width_minus_1;

    wire [BUFFER_ADDR_BITS+3-1:0] pixel_addr = x_in;
    wire [BUFFER_ADDR_BITS+3-1:0] pixel_bit_addr = pixel_addr << bpp_log2;

    assign pixel_read.enable = active;
    assign pixel_read.addr = pixel_bit_addr >> 3;

    reg active_1;
    reg [2:0] pixel_frac_addr;
    always @(posedge clk) begin
        active_1 <= active;
        pixel_frac_addr <= pixel_bit_addr[2:0];
    end

    // Stage 1

    wire [PIXEL_BITS-1:0] extracted_pixel = extract_pixel(.bpp_log2(bpp_log2), .pixel_bits(pixel_read.data), .bit_addr(pixel_frac_addr), .high_bits(pal_bits), .keep_0(1));

    reg [PIXEL_BITS-1:0] pixel_2;    
    always @(posedge clk) pixel_2 <= active_1 ? extracted_pixel : 0;

    // Stage 2

    reg [PIXEL_BITS-1:0] pixel_3;
    always @(posedge clk) pixel_3 <= pixel_2;

    // Stage 3

    assign pixel = pixel_3;
endmodule


module sprite_setup #(parameter Y_BITS = 9, PITCH_L2_BITS = 3, VRAM_ADDR_BITS = 15) (
        input [Y_BITS-1:0] y_in,
        input [Y_BITS-1:0] height_minus_1,
        input [PITCH_L2_BITS-1:0] pitch_log2,

        output active,
        output [VRAM_ADDR_BITS-1:0] row_addr
    );
    
    wire [Y_BITS-1:0] y = y_in;
    assign active = (y <= height_minus_1);
    assign row_addr = y << pitch_log2;    
endmodule


module sprite_line_buffer_transfer #(parameter VRAM_ADDR_BITS = 15, BUFFER_ADDR_BITS = 6) (
        input clk,

        input start,
        output working,

        input [VRAM_ADDR_BITS-1:0] start_addr,
        input [BUFFER_ADDR_BITS-1:0] width_minus_1, // in transfers

        ReadChannel.Master vram_read,
        WriteChannel.Master buffer_write
    );
    
    reg reading = 0;
    reg writing = 0;

    reg [VRAM_ADDR_BITS-1:0] read_addr;
    reg [BUFFER_ADDR_BITS-1:0] write_addr, curr_width_minus_1;

    assign vram_read.enable = reading;
    assign vram_read.addr = read_addr;

    assign buffer_write.enable = writing;
    assign buffer_write.addr = write_addr;
    assign buffer_write.data = vram_read.data;

    always @(posedge clk) begin
        if (start) begin
            reading <= 1;
            read_addr <= start_addr;
            write_addr <= 0;
            curr_width_minus_1 <= width_minus_1;
        end else begin
            if (reading) read_addr  <= read_addr  + 1;
            if (writing) write_addr <= write_addr + 1;
    
            if (write_addr == curr_width_minus_1) begin
                writing <= 0;            
                reading <= 0; // Could deassert the read this cycle instead
            end else begin
                writing <= reading;
            end
        end
    end
    assign working = reading || writing;
endmodule


module sprite_row #(parameter X_BITS = 10, PIXEL_BITS = 8, BUFFER_ADDR_BITS = 6) (
        input clk,

        input [X_BITS-1:0] x_in,

        output [PIXEL_BITS-1:0] pixel,

        input reg_write_enable, buffer_write_enable,
        WriteChannel.Slave reg_write,
        WriteChannel.Slave buffer_write
    );
    reg [X_BITS-1:0] sprite_x = 0;
    reg [X_BITS-1:0] width_minus_1 = 63;
    reg [1:0] bpp_log2;
    reg [PIXEL_BITS-1:0] pal_bits;
    reg [1:0] x_shift;

    always @(posedge clk) if (reg_write_enable && reg_write.enable) begin
        if (reg_write.addr == 0) sprite_x <= reg_write.data;
        else if (reg_write.addr == 1) width_minus_1 <= reg_write.data;
        else if (reg_write.addr == 2) bpp_log2 <= reg_write.data;
        else if (reg_write.addr == 3) pal_bits <= reg_write.data;
        else if (reg_write.addr == 4) x_shift <= reg_write.data;
    end


    (* ram_style = "distributed" *) reg [7:0] sprite_line_buffer[0:2**BUFFER_ADDR_BITS - 1];
    initial begin
        for (int i=0; i < 2**BUFFER_ADDR_BITS; i++) sprite_line_buffer[i] = ((i & 24) == 0) ||  ((i & 24) == 24) ? i : 0;
    end

    always @(posedge clk) if (buffer_write_enable && buffer_write.enable) sprite_line_buffer[buffer_write.addr] <= buffer_write.data;

    ReadChannel #(.ADDR_SIZE(BUFFER_ADDR_BITS)) sprite_pixel_read();

    always @(posedge clk) begin
        if (sprite_pixel_read.enable) sprite_pixel_read.data <= sprite_line_buffer[sprite_pixel_read.addr];
    end    

    sprite_row_renderer #(.X_BITS(X_BITS), .WIDTH_BITS(X_BITS), .PIXEL_BITS(PIXEL_BITS), .BUFFER_ADDR_BITS(BUFFER_ADDR_BITS)) sprites(
        .clk(clk),
        .bpp_log2(bpp_log2), .pal_bits(pal_bits),
        .x_in($signed(x_in - sprite_x) >>> x_shift),
        .width_minus_1(width_minus_1),
        .pixel_read(sprite_pixel_read),
        .pixel(pixel)
    );    
endmodule

module pixel_merge #(parameter PIXEL_BITS = 8, NUM_OUTPUT_PIXELS = 1) (
        input [PIXEL_BITS-1:0] pixels_in[NUM_OUTPUT_PIXELS*2],
        output [PIXEL_BITS-1:0] pixels_out[NUM_OUTPUT_PIXELS]
    );
    generate
        genvar k;
        for (k=0; k < NUM_OUTPUT_PIXELS; k++) begin
            assign pixels_out[k] = pixels_in[2*k] == 0 ? pixels_in[2*k+1] : pixels_in[2*k];
        end
    endgenerate
endmodule

module sprite_renderer #(parameter X_BITS = 10, Y_BITS = 9, WIDTH_BITS = 6, PIXEL_BITS = 8, PITCH_L2_BITS = 3, VRAM_ADDR_BITS = 15, BUFFER_ADDR_BITS = 6, SPRITE_WIDTH_BITS = 6, SPRITE_ADDR_BITS = 3) (
        input clk,

        input [X_BITS-1:0] x_in,
        input [Y_BITS-1:0] y_in,

        input start_sprites_transfer,

        output [PIXEL_BITS-1:0] pixel,

        WriteChannel.Slave reg_write,
        ReadChannel.Master vram_read
    );
    
    localparam ROW_REG_ADDR_BITS = 3;
    WriteChannel #(.ADDR_SIZE(ROW_REG_ADDR_BITS), .DATA_WIDTH(32)) row_reg_write();

    localparam NUM_SPRITES = 2**SPRITE_ADDR_BITS;

    localparam SETUP_REG_ADDR_BITS = 3;
    localparam NUM_SETUP_REGS_PER_SPRITE = 2**SETUP_REG_ADDR_BITS;
    localparam NUM_SETUP_REGS = NUM_SETUP_REGS_PER_SPRITE * NUM_SPRITES;
    reg [31:0] registers[NUM_SETUP_REGS];
    
    initial begin
        for (int i=0; i < NUM_SETUP_REGS; i++) registers[i] = 0;
        for (int i=0; i < NUM_SPRITES; i++) begin
            registers[i*NUM_SETUP_REGS_PER_SPRITE + 1] = 63; // sprite_height_minus_1
            registers[i*NUM_SETUP_REGS_PER_SPRITE + 4] = 63; // sprite_row_bytes_minus_1
            registers[i*NUM_SETUP_REGS_PER_SPRITE + 2] = 6; // sprite_pitch_log2
        end
    end

    reg [SPRITE_ADDR_BITS-1:0] sprite_index = 0;
    wire [SPRITE_ADDR_BITS+SETUP_REG_ADDR_BITS-1:0] setup_reg_base = sprite_index << SETUP_REG_ADDR_BITS;

    wire [Y_BITS-1:0] sprite_y = registers[setup_reg_base | 0];
    wire [Y_BITS-1:0] sprite_height_minus_1 = registers[setup_reg_base | 1];
    wire [2:0] sprite_pitch_log2 = registers[setup_reg_base | 2];
    wire [VRAM_ADDR_BITS-1:0] sprite_base_addr = registers[setup_reg_base | 3];
    wire [BUFFER_ADDR_BITS-1:0] sprite_row_bytes_minus_1 = registers[setup_reg_base | 4];
    wire [1:0] y_shift = registers[setup_reg_base | 5];

    always @(posedge clk) if (reg_write.enable && reg_write.addr < NUM_SETUP_REGS) registers[reg_write.addr] <= reg_write.data;
    
    assign row_reg_write.enable = reg_write.enable && (reg_write.addr >= NUM_SETUP_REGS);
    assign row_reg_write.addr = reg_write.addr - NUM_SETUP_REGS;
    assign row_reg_write.data = reg_write.data;
    wire [SPRITE_ADDR_BITS-1:0] row_reg_write_index = (reg_write.addr - NUM_SETUP_REGS) >> ROW_REG_ADDR_BITS;

    // ## Sprite setup

    wire start_row_transfer;

    wire sprite_active_row;
    wire [VRAM_ADDR_BITS-1:0] sprite_row_addr;

    sprite_setup #(.Y_BITS(Y_BITS), .PITCH_L2_BITS(PITCH_L2_BITS), .VRAM_ADDR_BITS(VRAM_ADDR_BITS)) sprite_setup_inst (
        .y_in($signed(y_in - sprite_y + 1'd1) >>> y_shift), .height_minus_1(sprite_height_minus_1), .pitch_log2(sprite_pitch_log2),
        .active(sprite_active_row), .row_addr(sprite_row_addr)
    );

    // ## Line buffer transfer

    WriteChannel #(.ADDR_SIZE(BUFFER_ADDR_BITS), .DATA_WIDTH(PIXEL_BITS)) buffer_write();

    reg [SPRITE_ADDR_BITS-1:0] transfer_sprite_index = 0;
    reg reg_sprite_row_active[NUM_SPRITES];
    always @(posedge clk) if (start_row_transfer) begin
        transfer_sprite_index <= sprite_index; 
        reg_sprite_row_active[sprite_index] <= sprite_active_row;
    end

    wire transfer_active;

    sprite_line_buffer_transfer #(.VRAM_ADDR_BITS(VRAM_ADDR_BITS), .BUFFER_ADDR_BITS(BUFFER_ADDR_BITS)) sprite_line_buffer_transfer_inst (
        .clk(clk),
        .start(start_row_transfer && sprite_active_row),
        .start_addr(sprite_base_addr + sprite_row_addr),
        .width_minus_1(sprite_row_bytes_minus_1),
        .working(transfer_active),
        .vram_read(vram_read), .buffer_write(buffer_write)
    );

    reg setup_active = 0;
    wire last_sprite = (sprite_index == NUM_SPRITES - 1);
    assign start_row_transfer = (setup_active && !transfer_active);

    always @(posedge clk) begin
        if (start_sprites_transfer) begin
            setup_active <= 1;
            sprite_index <= 0;
        end else if (setup_active && !transfer_active) begin
            sprite_index <= sprite_index + 1;
            if (last_sprite) setup_active <= 0;
        end
    end

    // ## Sprite rows

    wire [PIXEL_BITS-1:0] pixels[NUM_SPRITES];

    generate
        genvar k;
        for (k = 0; k < NUM_SPRITES; k++) begin : sprites
            wire [PIXEL_BITS-1:0] row_pixel;
            sprite_row #(.X_BITS(X_BITS), .PIXEL_BITS(PIXEL_BITS), .BUFFER_ADDR_BITS(BUFFER_ADDR_BITS)) row(
                .clk(clk),
                .x_in(x_in),
                .pixel(row_pixel),
                .reg_write_enable(row_reg_write_index == k),
                .buffer_write_enable(transfer_sprite_index == k),
                .reg_write(row_reg_write), .buffer_write(buffer_write)
            );
            assign pixels[k] = reg_sprite_row_active[k] ? row_pixel : 0;
        end : sprites
    endgenerate

    wire [PIXEL_BITS-1:0] pixels_4[4];
    wire [PIXEL_BITS-1:0] pixels_2[2];
    wire [PIXEL_BITS-1:0] pixels_1[1];
    pixel_merge #(.PIXEL_BITS(PIXEL_BITS), .NUM_OUTPUT_PIXELS(4)) merge8(.pixels_in(pixels), .pixels_out(pixels_4));
    pixel_merge #(.PIXEL_BITS(PIXEL_BITS), .NUM_OUTPUT_PIXELS(2)) merge4(.pixels_in(pixels_4), .pixels_out(pixels_2));
    pixel_merge #(.PIXEL_BITS(PIXEL_BITS), .NUM_OUTPUT_PIXELS(1)) merge2(.pixels_in(pixels_2), .pixels_out(pixels_1));
    assign pixel = pixels_1[0];

    //assign pixel = pixels[0] == 0 ? pixels[1] : pixels[0];
endmodule

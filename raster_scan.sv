`timescale 1ns / 1ps

module raster_scan #(parameter COORD_BITS = 12, HBLANK_START_REPORT_DELAY = 0) (
        input clk,

        input ModeLine mode,

        output PixelState state,
        output reg [COORD_BITS-1:0] x, y,
        output reg new_frame, hblank_start
    );

    wire [COORD_BITS-1:0] vsync_y0 = mode.VSYNC_Y0 - mode.LOGICAL_HEIGHT;
    wire [COORD_BITS-1:0] vsync_y1 = mode.VSYNC_Y1 - mode.LOGICAL_HEIGHT;
    wire [COORD_BITS-1:0] max_y = -1;

    initial begin
        x <= 0;
        y <= 0;
        state <= '{0,0,0}; 
    end

    wire last_x = (x == (mode.LOGICAL_WIDTH-1));
    wire last_y = (y == max_y);

    always @(posedge clk) begin
        state.draw <= (x < mode.DRAW_WIDTH) && (y < mode.DRAW_HEIGHT);

        x <= last_x ? 0 : x + 1;
        if (last_x) y <= (y == mode.DRAW_HEIGHT-1) ? (mode.DRAW_HEIGHT - mode.LOGICAL_HEIGHT) : y + 1;

        new_frame <= (last_x && last_y);
        hblank_start <= (x == (mode.DRAW_WIDTH + HBLANK_START_REPORT_DELAY));

        state.hsync <= (x >= mode.HSYNC_X0) && (x < mode.HSYNC_X1);
        state.vsync <= (y >= vsync_y0) && (y < vsync_y1);
    end
endmodule

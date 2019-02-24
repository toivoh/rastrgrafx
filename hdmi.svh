`ifndef __hdmi_svh
`define __hdmi_svh

typedef struct {
    logic hsync;
    logic vsync;
    logic draw;
} PixelState;

typedef struct {
    logic [7:0] r, g, b; 
} RGB24;

typedef struct packed {
    logic [7:0] r, g, b;
    logic hsync, vsync, draw;
    logic wren;
} RGB24sync;

typedef struct {
    int FPS;
    real PIXEL_RATE; // MHz
    int DRAW_WIDTH;
    int HSYNC_X0;
    int HSYNC_X1;
    int LOGICAL_WIDTH;

    int DRAW_HEIGHT;
    int VSYNC_Y0;
    int VSYNC_Y1;
    int LOGICAL_HEIGHT;
} ModeLine;
 
//                                      fps    pixclk(MHz)    w     x0    x1    wtot   h     y0    y1    htot  
parameter ModeLine mode_640x480_60   = '{ 60,   25.0,         640,  656,  752,  800,   480,  490,  492,  525};
parameter ModeLine mode_1024x768_60  = '{ 60,   65.0,        1024, 1048, 1184, 1344,   768,  771,  777,  806};
parameter ModeLine mode_1280x720_60  = '{ 60,   74.25,       1280, 1390, 1430, 1650,   720,  725,  730,  750};
parameter ModeLine mode_1280x960_60  = '{ 60,  108.0,        1280, 1376, 1488, 1800,   960,  961,  964, 1000};
parameter ModeLine mode_1280x1024_60 = '{ 60,  108.0,        1280, 1328, 1440, 1688,  1024, 1025, 1028, 1066};
parameter ModeLine mode_1920x1080_30 = '{ 30,   89.01,       1920, 2448, 2492, 2640,  1080, 1084, 1089, 1125};
parameter ModeLine mode_1920x1080_40 = '{ 40,  118.8,        1920, 2448, 2492, 2640,  1080, 1084, 1089, 1125};

parameter ModeLine mode_150x100_fake = '{ 60,   25.0,         150,  160,  170,  200,   100,  110,  120,  150};
parameter ModeLine mode_70x70_fake   = '{ 60,   25.0,          70,   80,   90,  100,    70,   80,   90,  100};

`endif // __hdmi_svh

rastrgrafx
==========
rastrgrafx is an FPGA implementation of a simple scanline based 2d graphics engine with tilemap and sprites.

The focus so far is on making a simple but customisable and extendable engine using a minimum of trickery. First and foremost, this has meant to try to keep the number of registers that hold actual state to a minimum (pipeline registers are ok). This also means that scanline effects should be very applicable to the engine: registers are sampled when they are used, or if need be, during hblank for the line before.

Features:
- Tilemap and sprite graphics
- 256 color palette
- Properties that can be mixed between the tilemap and different sprites:
	- 1/2/4/8 bpp, subpalette selectable per sprite and tile
		- Packed pixel format
	- Power of 2 upscaling
- Resolution depends on how fast you can clock your FPGA, I've done 1280x1024@60Hz so far
- Tilemap
	- Smooth scrolling
	- Independent wraparound in x and y
- Sprites
	- Sprite data is buffered during the hblank preceding a line
		- Limitations are sprite row buffer size and sum of widths of active sprites on the same line
	- Arbitrary height
- Pixel RAM
	- Shared by tile and sprite graphics

Block RAMs in the FPGA are used for tilemaps, pixel RAM, and palette, could be divided as appropriate.

The engine in `main.sv` uses a single tilemap as background, but the only thing that stops you from having several is to figure out a way to divide the access to tilemap and pixel RAM (e.g. time division using multiple clock cycles per pixel, or wider than 8 bit internal memory interface to the block RAMs).

A small demo can be seen at https://youtu.be/NOukEOLJctY

Design
------
The code is written as a set of modules that could be combined in somewhat different ways. It is implemented as a pipeline where modifications at different stages will have different kinds of effects on the visual result.

### Top module
The top module, `main.sv`, brings together all the parts of the pipeline. Currently, it looks something like this:

                       tilemap RAM
                            A
                            |
                            V    pixel index
                      --> tiles --------------
                     /      A                 \
                    /       |                  \
            x, y,  /        V                   V   pixel            rgb
    raster -------+      switch <--> pixel     mix ------> palette ------>
     scan   events \        A         RAM       A   index    RAM    ----->
          \         \       |                  /                   / sync
           \         \      V                 /                   /
            \         -> sprites -------------                   /
             \                    pixel index                   /
              \ hsync, vsync, blanking                         /
               -------------------> delay ---------------------

Parts:
- The `raster_scan` module sweeps over the raster pattern for the desired video mode and outputs the coordinate of the current screen pixel,
  along with sync and blanking signals, and events needed by later steps.
- The tiles are rendered by module `tilemap_renderer`, which reads both tilemap and pixel RAM.
- The sprites are rendered by module `sprite_renderer`, which also reads graphics from pixel RAM.
- Access to pixel RAM is shared through a switch that lets the sprites read during horizontal blanking, and the tiles otherwise.
- The pixels are mixed: a sprite pixel index of 0 is translucent and lets the tile background through.
- Finally, the pixel is translated from index to RGB through the palette RAM.
- The above steps are pipelined over a few cycles, so the hsync, vsync, and blanking signals are delayed for the same number of cycles to match up at the output.

All of the RAMs are instantiated in the top module; the tile and sprite renderers use the read interface `ReadChannel` to request data to be delivered the next cycle. This way, the submodules don't have to make as many assumptions about how the memories are set up and connected.

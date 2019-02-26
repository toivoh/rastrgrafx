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

### Tilemap renderer
The `tilemap_renderer` module implements a pipeline that looks something like this:

                                                 tilemap RAM  tile palette index
                                                       A    --------------------------------------------------
                                                       |   /                                                  \
                                                       V  / tile index                    bit addr             \
                                         -> tile ---> read ----                         ------------            \
                                        /   addr     tilemap   \                       /            \            \
     x, y           x, y          x, y /                        V                     /              V            V           pixel
    ------> scroll ------> scale -----+                        pixel addr ---> bpp --+--> read ---> extract ---> set palette ------>
                                       \                        A             shift       pixel      pixel                    index
                                        \ x, y in tile         /                            A
                                         ----------------------                             |
                                                                                            V
                                                                                        pixel RAM

The pixel data is transformed into a few different forms as it goes through the pipeline:
- (x, y) coordinates - In this form, it's easy to apply scrolling and scaling
- (tile index, coordinates in tile)
- Pixel adress - Downshifted to support lower bits per pixel (bpp) modes
- Pixel data - Processed to extract the desired bits in lower bpp modes
	- The unused bits are filled in from the palette data index read from the tilemap, unless the pixel is 0 (transparent)

### Sprite renderer
The `sprite_renderer` module is split into an x (per pixel) and a y (per scanline) part, where the y part sets up the x part:

                                            :
           { -------- per scanline -------- : ------- per pixel -------- }
           { --- shared between sprites --- : -- per sprite -- | - mix - } 
                                            :

         y            row addr,           bytes
        ----> sprite --------------> row ------> row buffers
              setup   active flag  transfer           A
                A                 A  /  A   :         |
                | sprite index,  /  /   |   :   x     V   pixels        pixel
                +----------------  /    |   :  ----> row --------> mix ------->
                | start transfer  /     |   :     renderers
     hblank     |                /      V    
    -------> control <-----------   pixel RAM
     start               done

The flow is a bit more complex than for the tilemap:
- When hblank starts, the `sprite_renderer` module loops over each sprite in turn: (these resources are shared between the sprites)
	- `sprite_setup` figures out the pixel RAM address to read the next sprite row from, and whether it will be visible on that line
	- `sprite_line_buffer_transfer` copies the data bytes for the row from pixel RAM to the sprite's row buffer, if it will be visible
- Each sprite has it's own `sprite_row` instance
	- Assumes that the row buffer has already been filled with pixel data for the current row
	- Outputs one pixel for each x position (0 when outside the sprite)
- The pixels are mixed to output the first one with a nonzero color index

The y part reads its registers during hblank, while the x part reads its registers continuously.
The row transfers need to finish before the hblank period ends, or the sprites will try to read pixel RAM at the same time as the tile map. Also, the sprites might show up wrong because their row buffers weren't updated in time: the only safe time to update the row buffers in this design is during hblank.

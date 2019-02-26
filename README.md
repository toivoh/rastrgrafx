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

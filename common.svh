`ifndef __common_svh
`define __common_svh

interface ReadChannel #(parameter ADDR_SIZE = 11, DATA_WIDTH = 8);
    logic [ADDR_SIZE-1:0] addr;
    logic enable;
    logic [DATA_WIDTH-1:0] data;

    modport Master (output addr, enable, input  data);
    modport Slave  (input  addr, enable, output data);
endinterface

interface WriteChannel #(parameter ADDR_SIZE = 11, DATA_WIDTH = 8);
    logic [ADDR_SIZE-1:0] addr;
    logic [DATA_WIDTH-1:0] data;
    logic enable;

    modport Master (output addr, data, enable);
    modport Slave  (input  addr, data, enable);
endinterface

function logic [7:0] extract_pixel(input [1:0] bpp_log2, input logic [7:0] pixel_bits, input logic [2:0] bit_addr, input logic [7:0] high_bits, input logic keep_0);
    logic [7:0] bits, combined_bits;
    case (bpp_log2)
        2'd0: begin bits = pixel_bits[bit_addr]; combined_bits = {high_bits[7:1], bits[0]}; end 
        2'd1: begin bits = pixel_bits[(bit_addr & 6) +: 2]; combined_bits = {high_bits[7:2], bits[1:0]}; end
        2'd2: begin bits = pixel_bits[(bit_addr & 4) +: 4]; combined_bits = {high_bits[7:4], bits[3:0]}; end
        2'd3: begin bits = pixel_bits; combined_bits = pixel_bits; end
    endcase
    extract_pixel = keep_0 && (bits == 0) ? 0 : combined_bits;
endfunction

`endif // __common_svh

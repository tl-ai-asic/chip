`timescale 1ns/1ps

module riscv32im_lsu_format (
  input  logic [2:0]  funct3_i,
  input  logic [1:0]  addr_lsb_i,
  input  logic [31:0] store_data_i,
  input  logic [31:0] first_rdata_i,
  input  logic [31:0] second_rdata_i,

  output logic        access_crosses_word_o,
  output logic [3:0]  load_mask_o,
  output logic [3:0]  store_mask_o,
  output logic [3:0]  second_mask_o,
  output logic [31:0] store_data_lane_o,
  output logic [31:0] second_store_data_o,
  output logic [31:0] load_data_o,
  output logic [31:0] split_word_o
);
  logic [2:0]  access_size;
  logic [2:0]  last_byte;
  logic [2:0]  overflow;
  logic [2:0]  first_bytes;
  logic [63:0] load_window;
  logic [31:0] shifted_load;
  logic [7:0]  byte_value;
  logic [15:0] half_value;

  always_comb begin
    unique case (funct3_i)
      3'b000,
      3'b100: access_size = 3'd1;
      3'b001,
      3'b101: access_size = 3'd2;
      3'b010: access_size = 3'd4;
      default: access_size = 3'd0;
    endcase

    last_byte = {1'b0, addr_lsb_i} + access_size - 3'd1;
    access_crosses_word_o = last_byte[2];
    overflow = ({1'b0, addr_lsb_i} + access_size) - 3'd4;
    first_bytes = 3'd4 - {1'b0, addr_lsb_i};

    unique case (funct3_i)
      3'b000,
      3'b100: load_mask_o = 4'b0001 << addr_lsb_i;
      3'b001,
      3'b101: load_mask_o = 4'b0011 << addr_lsb_i;
      3'b010: load_mask_o = 4'b1111 << addr_lsb_i;
      default: load_mask_o = 4'b0000;
    endcase

    unique case (funct3_i)
      3'b000: store_mask_o = 4'b0001 << addr_lsb_i;
      3'b001: store_mask_o = 4'b0011 << addr_lsb_i;
      3'b010: store_mask_o = 4'b1111 << addr_lsb_i;
      default: store_mask_o = 4'b0000;
    endcase

    unique case (funct3_i)
      3'b000: store_data_lane_o = {24'h0, store_data_i[7:0]} << (addr_lsb_i * 8);
      3'b001: store_data_lane_o = {16'h0, store_data_i[15:0]} << (addr_lsb_i * 8);
      3'b010: store_data_lane_o = store_data_i << (addr_lsb_i * 8);
      default: store_data_lane_o = 32'h0000_0000;
    endcase

    if (access_crosses_word_o) begin
      second_mask_o = 4'hf >> (4 - overflow);
      second_store_data_o = store_data_i >> (first_bytes * 8);
    end else begin
      second_mask_o = 4'h0;
      second_store_data_o = 32'h0000_0000;
    end

    load_window = {second_rdata_i, first_rdata_i} >> (addr_lsb_i * 8);
    shifted_load = load_window[31:0];
    split_word_o = shifted_load;
    byte_value = shifted_load[7:0];
    half_value = shifted_load[15:0];

    unique case (funct3_i)
      3'b000: load_data_o = {{24{byte_value[7]}}, byte_value};
      3'b001: load_data_o = {{16{half_value[15]}}, half_value};
      3'b010: load_data_o = shifted_load;
      3'b100: load_data_o = {24'h0, byte_value};
      3'b101: load_data_o = {16'h0, half_value};
      default: load_data_o = 32'h0000_0000;
    endcase
  end
endmodule

`timescale 1ns/1ps

module riscv32im_lsu (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        start_i,
  input  logic        write_i,
  input  logic [2:0]  funct3_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] store_data_i,

  output logic        busy_o,
  output logic        done_o,
  output logic        error_o,
  output logic [31:0] load_data_o,
  output logic [31:0] rvfi_mem_addr_o,
  output logic [3:0]  rvfi_mem_rmask_o,
  output logic [3:0]  rvfi_mem_wmask_o,
  output logic [31:0] rvfi_mem_rdata_o,
  output logic [31:0] rvfi_mem_wdata_o,

  output logic        dmem_req_valid,
  input  logic        dmem_req_ready,
  output logic        dmem_req_write,
  output logic [31:0] dmem_req_addr,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0]  dmem_req_wstrb,
  input  logic        dmem_rsp_valid,
  input  logic [31:0] dmem_rsp_rdata,
  input  logic        dmem_rsp_err
);
  typedef enum logic [2:0] {
    LSU_IDLE,
    LSU_REQ1,
    LSU_RSP1,
    LSU_REQ2,
    LSU_RSP2
  } lsu_state_e;

  lsu_state_e state_q;

  logic        write_q;
  logic [2:0]  funct3_q;
  logic [31:0] addr_q;
  logic [31:0] store_data_q;
  logic [31:0] first_rdata_q;
  logic [31:0] beat1_wdata_q;
  logic [3:0]  beat1_wmask_q;
  logic [3:0]  beat1_rmask_q;

  logic        start_access_crosses;
  logic [3:0]  start_load_mask;
  logic [3:0]  start_store_mask;
  logic [3:0]  start_second_mask;
  logic [31:0] start_store_data_lane;
  logic [31:0] start_second_store_data;
  logic [31:0] start_load_data;
  logic [31:0] start_split_word;

  logic [31:0] req_first_rdata;
  logic [31:0] req_second_rdata;
  logic        req_access_crosses;
  logic [3:0]  req_load_mask;
  logic [3:0]  req_store_mask;
  logic [3:0]  req_second_mask;
  logic [31:0] req_store_data_lane;
  logic [31:0] req_second_store_data;
  logic [31:0] req_load_data;
  logic [31:0] req_split_word;

  assign req_first_rdata = (state_q == LSU_RSP2) ? first_rdata_q : dmem_rsp_rdata;
  assign req_second_rdata = (state_q == LSU_RSP2) ? dmem_rsp_rdata : 32'h0000_0000;

  riscv32im_lsu_format u_start_format (
    .funct3_i(funct3_i),
    .addr_lsb_i(addr_i[1:0]),
    .store_data_i(store_data_i),
    .first_rdata_i(32'h0000_0000),
    .second_rdata_i(32'h0000_0000),
    .access_crosses_word_o(start_access_crosses),
    .load_mask_o(start_load_mask),
    .store_mask_o(start_store_mask),
    .second_mask_o(start_second_mask),
    .store_data_lane_o(start_store_data_lane),
    .second_store_data_o(start_second_store_data),
    .load_data_o(start_load_data),
    .split_word_o(start_split_word)
  );

  riscv32im_lsu_format u_req_format (
    .funct3_i(funct3_q),
    .addr_lsb_i(addr_q[1:0]),
    .store_data_i(store_data_q),
    .first_rdata_i(req_first_rdata),
    .second_rdata_i(req_second_rdata),
    .access_crosses_word_o(req_access_crosses),
    .load_mask_o(req_load_mask),
    .store_mask_o(req_store_mask),
    .second_mask_o(req_second_mask),
    .store_data_lane_o(req_store_data_lane),
    .second_store_data_o(req_second_store_data),
    .load_data_o(req_load_data),
    .split_word_o(req_split_word)
  );

  assign busy_o = (state_q != LSU_IDLE);

  assign dmem_req_valid = ((state_q == LSU_REQ1) || (state_q == LSU_REQ2));
  assign dmem_req_write = write_q;
  assign dmem_req_addr = (state_q == LSU_REQ2) ? {addr_q[31:2] + 30'd1, 2'b00} : {addr_q[31:2], 2'b00};
  assign dmem_req_wdata = (state_q == LSU_REQ2) ? req_second_store_data : beat1_wdata_q;
  assign dmem_req_wstrb = write_q ? ((state_q == LSU_REQ2) ? req_second_mask : beat1_wmask_q) : 4'h0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= LSU_IDLE;
      write_q <= 1'b0;
      funct3_q <= 3'b000;
      addr_q <= 32'h0000_0000;
      store_data_q <= 32'h0000_0000;
      first_rdata_q <= 32'h0000_0000;
      beat1_wdata_q <= 32'h0000_0000;
      beat1_wmask_q <= 4'h0;
      beat1_rmask_q <= 4'h0;
      done_o <= 1'b0;
      error_o <= 1'b0;
      load_data_o <= 32'h0000_0000;
      rvfi_mem_addr_o <= 32'h0000_0000;
      rvfi_mem_rmask_o <= 4'h0;
      rvfi_mem_wmask_o <= 4'h0;
      rvfi_mem_rdata_o <= 32'h0000_0000;
      rvfi_mem_wdata_o <= 32'h0000_0000;
    end else begin
      done_o <= 1'b0;
      error_o <= 1'b0;

      unique case (state_q)
        LSU_IDLE: begin
          if (start_i) begin
            state_q <= LSU_REQ1;
            write_q <= write_i;
            funct3_q <= funct3_i;
            addr_q <= addr_i;
            store_data_q <= store_data_i;
            first_rdata_q <= 32'h0000_0000;
            beat1_wdata_q <= start_store_data_lane;
            beat1_wmask_q <= start_store_mask;
            beat1_rmask_q <= start_load_mask;
            load_data_o <= 32'h0000_0000;
            rvfi_mem_addr_o <= addr_i;
            rvfi_mem_rmask_o <= write_i ? 4'h0 : start_load_mask;
            rvfi_mem_wmask_o <= write_i ? start_store_mask : 4'h0;
            rvfi_mem_rdata_o <= 32'h0000_0000;
            rvfi_mem_wdata_o <= write_i ? start_store_data_lane : 32'h0000_0000;
          end
        end

        LSU_REQ1: begin
          if (dmem_req_ready) begin
            state_q <= LSU_RSP1;
          end
        end

        LSU_RSP1: begin
          if (dmem_rsp_valid) begin
            if (dmem_rsp_err) begin
              done_o <= 1'b1;
              error_o <= 1'b1;
              rvfi_mem_rdata_o <= dmem_rsp_rdata;
              state_q <= LSU_IDLE;
            end else if (req_access_crosses) begin
              first_rdata_q <= dmem_rsp_rdata;
              state_q <= LSU_REQ2;
            end else begin
              done_o <= 1'b1;
              load_data_o <= write_q ? 32'h0000_0000 : req_load_data;
              rvfi_mem_rdata_o <= dmem_rsp_rdata;
              state_q <= LSU_IDLE;
            end
          end
        end

        LSU_REQ2: begin
          if (dmem_req_ready) begin
            state_q <= LSU_RSP2;
          end
        end

        LSU_RSP2: begin
          if (dmem_rsp_valid) begin
            done_o <= 1'b1;
            error_o <= dmem_rsp_err;
            if (dmem_rsp_err) begin
              rvfi_mem_rdata_o <= first_rdata_q;
            end else begin
              load_data_o <= write_q ? 32'h0000_0000 : req_load_data;
              rvfi_mem_rdata_o <= write_q ? 32'h0000_0000 : req_split_word;
            end
            state_q <= LSU_IDLE;
          end
        end

        default: begin
          state_q <= LSU_IDLE;
        end
      endcase
    end
  end
endmodule

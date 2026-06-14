`timescale 1ns/1ps

module riscv32im_lsu (
  input  logic                       clk,
  input  logic                       rst_n,

  input  logic                       start_i,
  input  riscv32im_lsu_issue_info_t issue_i,
  output logic                       issue_ready_o,

  output logic                       rsp_valid_o,
  input  logic                       rsp_ready_i,
  output riscv32im_lsu_rsp_info_t   rsp_o,

  output logic                       dmem_req_valid,
  input  logic                       dmem_req_ready,
  output logic                       dmem_req_write,
  output logic [31:0]                dmem_req_addr,
  output logic [31:0]                dmem_req_wdata,
  output logic [3:0]                 dmem_req_wstrb,
  input  logic                       dmem_rsp_valid,
  input  logic [31:0]                dmem_rsp_rdata,
  input  logic                       dmem_rsp_err
);
  typedef enum logic [2:0] {
    LSU_IDLE,
    LSU_REQ1,
    LSU_RSP1,
    LSU_REQ2,
    LSU_RSP2
  } lsu_state_e;

  localparam logic [31:0] EXC_LOAD_ACCESS_FAULT  = 32'd5;
  localparam logic [31:0] EXC_STORE_ACCESS_FAULT = 32'd7;

  lsu_state_e state_q;

  riscv32im_lsu_issue_info_t entry0_q;
  riscv32im_lsu_issue_info_t entry1_q;
  riscv32im_lsu_issue_info_t head_entry;
  riscv32im_lsu_rsp_info_t   rsp_q;

  logic entry0_valid_q;
  logic entry1_valid_q;
  logic head_q;
  logic tail_q;
  logic [1:0] count_q;
  logic rsp_valid_q;

  logic [31:0] first_rdata_q;

  logic        issue_access_crosses;
  logic [3:0]  issue_load_mask;
  logic [3:0]  issue_store_mask;
  logic [3:0]  issue_second_mask;
  logic [31:0] issue_store_data_lane;
  logic [31:0] issue_second_store_data;
  logic [31:0] issue_load_data;
  logic [31:0] issue_split_word;

  logic        entry0_access_crosses;
  logic [3:0]  entry0_load_mask;
  logic [3:0]  entry0_store_mask;
  logic [3:0]  entry0_second_mask;
  logic [31:0] entry0_store_data_lane;
  logic [31:0] entry0_second_store_data;
  logic [31:0] entry0_load_data;
  logic [31:0] entry0_split_word;

  logic        entry1_access_crosses;
  logic [3:0]  entry1_load_mask;
  logic [3:0]  entry1_store_mask;
  logic [3:0]  entry1_second_mask;
  logic [31:0] entry1_store_data_lane;
  logic [31:0] entry1_second_store_data;
  logic [31:0] entry1_load_data;
  logic [31:0] entry1_split_word;

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

  logic [3:0]  issue_first_mask;
  logic [3:0]  entry0_first_mask;
  logic [3:0]  entry1_first_mask;
  logic [29:0] issue_word0;
  logic [29:0] issue_word1;
  logic [29:0] entry0_word0;
  logic [29:0] entry0_word1;
  logic [29:0] entry1_word0;
  logic [29:0] entry1_word1;
  logic        issue_entry0_overlap;
  logic        issue_entry1_overlap;
  logic        issue_fire;
  logic        complete_entry;

  assign head_entry = head_q ? entry1_q : entry0_q;

  assign req_first_rdata = (state_q == LSU_RSP2) ? first_rdata_q : dmem_rsp_rdata;
  assign req_second_rdata = (state_q == LSU_RSP2) ? dmem_rsp_rdata : 32'h0000_0000;

  riscv32im_lsu_format u_issue_format (
    .funct3_i(issue_i.funct3),
    .addr_lsb_i(issue_i.addr[1:0]),
    .store_data_i(issue_i.store_data),
    .first_rdata_i(32'h0000_0000),
    .second_rdata_i(32'h0000_0000),
    .access_crosses_word_o(issue_access_crosses),
    .load_mask_o(issue_load_mask),
    .store_mask_o(issue_store_mask),
    .second_mask_o(issue_second_mask),
    .store_data_lane_o(issue_store_data_lane),
    .second_store_data_o(issue_second_store_data),
    .load_data_o(issue_load_data),
    .split_word_o(issue_split_word)
  );

  riscv32im_lsu_format u_entry0_format (
    .funct3_i(entry0_q.funct3),
    .addr_lsb_i(entry0_q.addr[1:0]),
    .store_data_i(entry0_q.store_data),
    .first_rdata_i(32'h0000_0000),
    .second_rdata_i(32'h0000_0000),
    .access_crosses_word_o(entry0_access_crosses),
    .load_mask_o(entry0_load_mask),
    .store_mask_o(entry0_store_mask),
    .second_mask_o(entry0_second_mask),
    .store_data_lane_o(entry0_store_data_lane),
    .second_store_data_o(entry0_second_store_data),
    .load_data_o(entry0_load_data),
    .split_word_o(entry0_split_word)
  );

  riscv32im_lsu_format u_entry1_format (
    .funct3_i(entry1_q.funct3),
    .addr_lsb_i(entry1_q.addr[1:0]),
    .store_data_i(entry1_q.store_data),
    .first_rdata_i(32'h0000_0000),
    .second_rdata_i(32'h0000_0000),
    .access_crosses_word_o(entry1_access_crosses),
    .load_mask_o(entry1_load_mask),
    .store_mask_o(entry1_store_mask),
    .second_mask_o(entry1_second_mask),
    .store_data_lane_o(entry1_store_data_lane),
    .second_store_data_o(entry1_second_store_data),
    .load_data_o(entry1_load_data),
    .split_word_o(entry1_split_word)
  );

  riscv32im_lsu_format u_req_format (
    .funct3_i(head_entry.funct3),
    .addr_lsb_i(head_entry.addr[1:0]),
    .store_data_i(head_entry.store_data),
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

  assign issue_first_mask = issue_i.write ? issue_store_mask : issue_load_mask;
  assign entry0_first_mask = entry0_q.write ? entry0_store_mask : entry0_load_mask;
  assign entry1_first_mask = entry1_q.write ? entry1_store_mask : entry1_load_mask;

  assign issue_word0 = issue_i.addr[31:2];
  assign issue_word1 = issue_i.addr[31:2] + 30'd1;
  assign entry0_word0 = entry0_q.addr[31:2];
  assign entry0_word1 = entry0_q.addr[31:2] + 30'd1;
  assign entry1_word0 = entry1_q.addr[31:2];
  assign entry1_word1 = entry1_q.addr[31:2] + 30'd1;

  assign issue_entry0_overlap =
    entry0_valid_q &&
    (issue_i.write || entry0_q.write) &&
    (((issue_word0 == entry0_word0) && ((issue_first_mask & entry0_first_mask) != 4'h0)) ||
     (issue_access_crosses && (issue_word1 == entry0_word0) && ((issue_second_mask & entry0_first_mask) != 4'h0)) ||
     (entry0_access_crosses && (issue_word0 == entry0_word1) && ((issue_first_mask & entry0_second_mask) != 4'h0)) ||
     (issue_access_crosses && entry0_access_crosses && (issue_word1 == entry0_word1) && ((issue_second_mask & entry0_second_mask) != 4'h0)));

  assign issue_entry1_overlap =
    entry1_valid_q &&
    (issue_i.write || entry1_q.write) &&
    (((issue_word0 == entry1_word0) && ((issue_first_mask & entry1_first_mask) != 4'h0)) ||
     (issue_access_crosses && (issue_word1 == entry1_word0) && ((issue_second_mask & entry1_first_mask) != 4'h0)) ||
     (entry1_access_crosses && (issue_word0 == entry1_word1) && ((issue_first_mask & entry1_second_mask) != 4'h0)) ||
     (issue_access_crosses && entry1_access_crosses && (issue_word1 == entry1_word1) && ((issue_second_mask & entry1_second_mask) != 4'h0)));

  assign issue_ready_o = (count_q == 2'd0) && !rsp_valid_q;
  assign issue_fire = start_i && issue_ready_o;

  assign complete_entry = ((state_q == LSU_RSP1) && dmem_rsp_valid && (dmem_rsp_err || !req_access_crosses)) ||
                          ((state_q == LSU_RSP2) && dmem_rsp_valid);

  assign rsp_valid_o = rsp_valid_q;
  assign rsp_o = rsp_q;

  assign dmem_req_valid = ((state_q == LSU_REQ1) || (state_q == LSU_REQ2));
  assign dmem_req_write = head_entry.write;
  assign dmem_req_addr = (state_q == LSU_REQ2) ? {head_entry.addr[31:2] + 30'd1, 2'b00} : {head_entry.addr[31:2], 2'b00};
  assign dmem_req_wdata = (state_q == LSU_REQ2) ? req_second_store_data : req_store_data_lane;
  assign dmem_req_wstrb = head_entry.write ? ((state_q == LSU_REQ2) ? req_second_mask : req_store_mask) : 4'h0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= LSU_IDLE;
      entry0_q <= '0;
      entry1_q <= '0;
      rsp_q <= '0;
      entry0_valid_q <= 1'b0;
      entry1_valid_q <= 1'b0;
      head_q <= 1'b0;
      tail_q <= 1'b0;
      count_q <= 2'd0;
      rsp_valid_q <= 1'b0;
      first_rdata_q <= 32'h0000_0000;
    end else begin
      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end

      if (complete_entry) begin
        if (head_q) begin
          entry1_valid_q <= 1'b0;
        end else begin
          entry0_valid_q <= 1'b0;
        end
        head_q <= head_q + 1'b1;
      end

      if (issue_fire) begin
        if (tail_q) begin
          entry1_q <= issue_i;
          entry1_valid_q <= 1'b1;
        end else begin
          entry0_q <= issue_i;
          entry0_valid_q <= 1'b1;
        end
        tail_q <= tail_q + 1'b1;
      end

      unique case ({issue_fire, complete_entry})
        2'b10: count_q <= count_q + 2'd1;
        2'b01: count_q <= count_q - 2'd1;
        default: begin
        end
      endcase

      unique case (state_q)
        LSU_IDLE: begin
          if ((count_q != 2'd0) && !rsp_valid_q) begin
            state_q <= LSU_REQ1;
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
              rsp_valid_q <= 1'b1;
              rsp_q.trap <= 1'b1;
              rsp_q.trap_cause <= head_entry.write ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
              rsp_q.trap_tval <= head_entry.addr;
              rsp_q.insn <= head_entry.insn;
              rsp_q.pc_rdata <= head_entry.pc_rdata;
              rsp_q.pc_wdata <= head_entry.pc_wdata;
              rsp_q.rs1_addr <= head_entry.rs1_addr;
              rsp_q.rs2_addr <= head_entry.rs2_addr;
              rsp_q.rs1_rdata <= head_entry.rs1_rdata;
              rsp_q.rs2_rdata <= head_entry.rs2_rdata;
              rsp_q.rd_write <= 1'b0;
              rsp_q.rd_addr <= 5'd0;
              rsp_q.rd_wdata <= 32'h0000_0000;
              rsp_q.mem_addr <= head_entry.addr;
              rsp_q.mem_rmask <= head_entry.write ? 4'h0 : req_load_mask;
              rsp_q.mem_wmask <= head_entry.write ? req_store_mask : 4'h0;
              rsp_q.mem_rdata <= dmem_rsp_rdata;
              rsp_q.mem_wdata <= head_entry.write ? req_store_data_lane : 32'h0000_0000;
              state_q <= LSU_IDLE;
            end else if (req_access_crosses) begin
              first_rdata_q <= dmem_rsp_rdata;
              state_q <= LSU_REQ2;
            end else begin
              rsp_valid_q <= 1'b1;
              rsp_q.trap <= 1'b0;
              rsp_q.trap_cause <= 32'h0000_0000;
              rsp_q.trap_tval <= 32'h0000_0000;
              rsp_q.insn <= head_entry.insn;
              rsp_q.pc_rdata <= head_entry.pc_rdata;
              rsp_q.pc_wdata <= head_entry.pc_wdata;
              rsp_q.rs1_addr <= head_entry.rs1_addr;
              rsp_q.rs2_addr <= head_entry.rs2_addr;
              rsp_q.rs1_rdata <= head_entry.rs1_rdata;
              rsp_q.rs2_rdata <= head_entry.rs2_rdata;
              rsp_q.rd_write <= head_entry.rd_write;
              rsp_q.rd_addr <= head_entry.rd_addr;
              rsp_q.rd_wdata <= head_entry.write ? 32'h0000_0000 : req_load_data;
              rsp_q.mem_addr <= head_entry.addr;
              rsp_q.mem_rmask <= head_entry.write ? 4'h0 : req_load_mask;
              rsp_q.mem_wmask <= head_entry.write ? req_store_mask : 4'h0;
              rsp_q.mem_rdata <= dmem_rsp_rdata;
              rsp_q.mem_wdata <= head_entry.write ? req_store_data_lane : 32'h0000_0000;
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
            rsp_valid_q <= 1'b1;
            rsp_q.trap <= dmem_rsp_err;
            rsp_q.trap_cause <= dmem_rsp_err ? (head_entry.write ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT) : 32'h0000_0000;
            rsp_q.trap_tval <= dmem_rsp_err ? head_entry.addr : 32'h0000_0000;
            rsp_q.insn <= head_entry.insn;
            rsp_q.pc_rdata <= head_entry.pc_rdata;
            rsp_q.pc_wdata <= head_entry.pc_wdata;
            rsp_q.rs1_addr <= head_entry.rs1_addr;
            rsp_q.rs2_addr <= head_entry.rs2_addr;
            rsp_q.rs1_rdata <= head_entry.rs1_rdata;
            rsp_q.rs2_rdata <= head_entry.rs2_rdata;
            rsp_q.rd_write <= dmem_rsp_err ? 1'b0 : head_entry.rd_write;
            rsp_q.rd_addr <= dmem_rsp_err ? 5'd0 : head_entry.rd_addr;
            rsp_q.rd_wdata <= (dmem_rsp_err || head_entry.write) ? 32'h0000_0000 : req_load_data;
            rsp_q.mem_addr <= head_entry.addr;
            rsp_q.mem_rmask <= head_entry.write ? 4'h0 : req_load_mask;
            rsp_q.mem_wmask <= head_entry.write ? req_store_mask : 4'h0;
            rsp_q.mem_rdata <= dmem_rsp_err ? first_rdata_q : (head_entry.write ? 32'h0000_0000 : req_split_word);
            rsp_q.mem_wdata <= head_entry.write ? req_store_data_lane : 32'h0000_0000;
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

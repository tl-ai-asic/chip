`timescale 1ns/1ps

module crossbar #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH = 4,
  parameter logic [ADDR_WIDTH-1:0] AXI_BASE_ADDR = 'h0000_0000,
  parameter logic [ADDR_WIDTH-1:0] AXI_ADDR_MASK = 'hF000_0000,
  parameter logic [ADDR_WIDTH-1:0] APB_BASE_ADDR = 'h1000_0000,
  parameter logic [ADDR_WIDTH-1:0] APB_ADDR_MASK = 'hF000_0000
) (
  input  logic                    clk,
  input  logic                    rst_n,

  input  logic [ID_WIDTH-1:0]     s_axi_awid,
  input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
  input  logic [7:0]              s_axi_awlen,
  input  logic [2:0]              s_axi_awsize,
  input  logic [1:0]              s_axi_awburst,
  input  logic                    s_axi_awlock,
  input  logic [3:0]              s_axi_awcache,
  input  logic [2:0]              s_axi_awprot,
  input  logic [3:0]              s_axi_awqos,
  input  logic                    s_axi_awvalid,
  output logic                    s_axi_awready,
  input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
  input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
  input  logic                    s_axi_wlast,
  input  logic                    s_axi_wvalid,
  output logic                    s_axi_wready,
  output logic [ID_WIDTH-1:0]     s_axi_bid,
  output logic [1:0]              s_axi_bresp,
  output logic                    s_axi_bvalid,
  input  logic                    s_axi_bready,
  input  logic [ID_WIDTH-1:0]     s_axi_arid,
  input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
  input  logic [7:0]              s_axi_arlen,
  input  logic [2:0]              s_axi_arsize,
  input  logic [1:0]              s_axi_arburst,
  input  logic                    s_axi_arlock,
  input  logic [3:0]              s_axi_arcache,
  input  logic [2:0]              s_axi_arprot,
  input  logic [3:0]              s_axi_arqos,
  input  logic                    s_axi_arvalid,
  output logic                    s_axi_arready,
  output logic [ID_WIDTH-1:0]     s_axi_rid,
  output logic [DATA_WIDTH-1:0]   s_axi_rdata,
  output logic [1:0]              s_axi_rresp,
  output logic                    s_axi_rlast,
  output logic                    s_axi_rvalid,
  input  logic                    s_axi_rready,

  input  logic [ADDR_WIDTH-1:0]   s_axil_awaddr,
  input  logic [2:0]              s_axil_awprot,
  input  logic                    s_axil_awvalid,
  output logic                    s_axil_awready,
  input  logic [DATA_WIDTH-1:0]   s_axil_wdata,
  input  logic [DATA_WIDTH/8-1:0] s_axil_wstrb,
  input  logic                    s_axil_wvalid,
  output logic                    s_axil_wready,
  output logic [1:0]              s_axil_bresp,
  output logic                    s_axil_bvalid,
  input  logic                    s_axil_bready,
  input  logic [ADDR_WIDTH-1:0]   s_axil_araddr,
  input  logic [2:0]              s_axil_arprot,
  input  logic                    s_axil_arvalid,
  output logic                    s_axil_arready,
  output logic [DATA_WIDTH-1:0]   s_axil_rdata,
  output logic [1:0]              s_axil_rresp,
  output logic                    s_axil_rvalid,
  input  logic                    s_axil_rready,

  output logic [ID_WIDTH-1:0]     m_axi_awid,
  output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
  output logic [7:0]              m_axi_awlen,
  output logic [2:0]              m_axi_awsize,
  output logic [1:0]              m_axi_awburst,
  output logic                    m_axi_awlock,
  output logic [3:0]              m_axi_awcache,
  output logic [2:0]              m_axi_awprot,
  output logic [3:0]              m_axi_awqos,
  output logic                    m_axi_awvalid,
  input  logic                    m_axi_awready,
  output logic [DATA_WIDTH-1:0]   m_axi_wdata,
  output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
  output logic                    m_axi_wlast,
  output logic                    m_axi_wvalid,
  input  logic                    m_axi_wready,
  input  logic [ID_WIDTH-1:0]     m_axi_bid,
  input  logic [1:0]              m_axi_bresp,
  input  logic                    m_axi_bvalid,
  output logic                    m_axi_bready,
  output logic [ID_WIDTH-1:0]     m_axi_arid,
  output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
  output logic [7:0]              m_axi_arlen,
  output logic [2:0]              m_axi_arsize,
  output logic [1:0]              m_axi_arburst,
  output logic                    m_axi_arlock,
  output logic [3:0]              m_axi_arcache,
  output logic [2:0]              m_axi_arprot,
  output logic [3:0]              m_axi_arqos,
  output logic                    m_axi_arvalid,
  input  logic                    m_axi_arready,
  input  logic [ID_WIDTH-1:0]     m_axi_rid,
  input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
  input  logic [1:0]              m_axi_rresp,
  input  logic                    m_axi_rlast,
  input  logic                    m_axi_rvalid,
  output logic                    m_axi_rready,

  output logic [ADDR_WIDTH-1:0]   m_apb_paddr,
  output logic [2:0]              m_apb_pprot,
  output logic                    m_apb_psel,
  output logic                    m_apb_penable,
  output logic                    m_apb_pwrite,
  output logic [DATA_WIDTH-1:0]   m_apb_pwdata,
  output logic [DATA_WIDTH/8-1:0] m_apb_pstrb,
  input  logic [DATA_WIDTH-1:0]   m_apb_prdata,
  input  logic                    m_apb_pready,
  input  logic                    m_apb_pslverr
);
  localparam int STRB_WIDTH = DATA_WIDTH / 8;
  localparam logic [2:0] AXIL_SIZE = (STRB_WIDTH <= 1) ? 3'd0 :
                                    (STRB_WIDTH <= 2) ? 3'd1 :
                                    (STRB_WIDTH <= 4) ? 3'd2 :
                                    (STRB_WIDTH <= 8) ? 3'd3 :
                                    (STRB_WIDTH <= 16) ? 3'd4 : 3'd5;

  localparam logic [1:0] RESP_OKAY = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;
  localparam logic [1:0] BURST_FIXED = 2'b00;

  typedef enum logic [1:0] {
    ROUTE_AXI = 2'd0,
    ROUTE_APB = 2'd1,
    ROUTE_ERR = 2'd2
  } route_e;

  typedef enum logic {
    SRC_AXI = 1'b0,
    SRC_AXIL = 1'b1
  } src_e;

  typedef enum logic [3:0] {
    WR_IDLE,
    WR_AXI_AW,
    WR_AXI_W,
    WR_AXI_B,
    WR_APB_W,
    WR_APB_RSP,
    WR_ERR_W,
    WR_RESP
  } wr_state_e;

  typedef enum logic [3:0] {
    RD_IDLE,
    RD_AXI_AR,
    RD_AXI_R,
    RD_APB_REQ,
    RD_APB_RSP,
    RD_SEND,
    RD_ERR_SEND
  } rd_state_e;

  typedef enum logic [1:0] {
    APB_IDLE,
    APB_SETUP,
    APB_ACCESS,
    APB_RESP
  } apb_state_e;

  typedef enum logic {
    APB_GRANT_WR = 1'b0,
    APB_GRANT_RD = 1'b1
  } apb_grant_e;

  function automatic logic region_match(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [ADDR_WIDTH-1:0] base,
    input logic [ADDR_WIDTH-1:0] mask
  );
    region_match = ((addr & mask) == (base & mask));
  endfunction

  function automatic route_e decode_route(input logic [ADDR_WIDTH-1:0] addr);
    if (region_match(addr, AXI_BASE_ADDR, AXI_ADDR_MASK)) begin
      decode_route = ROUTE_AXI;
    end else if (region_match(addr, APB_BASE_ADDR, APB_ADDR_MASK)) begin
      decode_route = ROUTE_APB;
    end else begin
      decode_route = ROUTE_ERR;
    end
  endfunction

  function automatic logic [ADDR_WIDTH-1:0] next_burst_addr(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    logic [ADDR_WIDTH-1:0] increment;
    begin
      increment = {{(ADDR_WIDTH-1){1'b0}}, 1'b1} << size;
      if (burst == BURST_FIXED) begin
        next_burst_addr = addr;
      end else begin
        next_burst_addr = addr + increment;
      end
    end
  endfunction

  logic axil_aw_valid_q, axil_aw_valid_d;
  logic [ADDR_WIDTH-1:0] axil_awaddr_q, axil_awaddr_d;
  logic [2:0] axil_awprot_q, axil_awprot_d;
  logic axil_w_valid_q, axil_w_valid_d;
  logic [DATA_WIDTH-1:0] axil_wdata_q, axil_wdata_d;
  logic [STRB_WIDTH-1:0] axil_wstrb_q, axil_wstrb_d;
  logic axil_ar_valid_q, axil_ar_valid_d;
  logic [ADDR_WIDTH-1:0] axil_araddr_q, axil_araddr_d;
  logic [2:0] axil_arprot_q, axil_arprot_d;

  wr_state_e wr_state_q, wr_state_d;
  src_e wr_src_q, wr_src_d;
  route_e wr_route_q, wr_route_d;
  logic [ID_WIDTH-1:0] wr_id_q, wr_id_d;
  logic [ADDR_WIDTH-1:0] wr_addr_q, wr_addr_d;
  logic [7:0] wr_len_q, wr_len_d;
  logic [2:0] wr_size_q, wr_size_d;
  logic [1:0] wr_burst_q, wr_burst_d;
  logic wr_lock_q, wr_lock_d;
  logic [3:0] wr_cache_q, wr_cache_d;
  logic [2:0] wr_prot_q, wr_prot_d;
  logic [3:0] wr_qos_q, wr_qos_d;
  logic [8:0] wr_beats_left_q, wr_beats_left_d;
  logic [DATA_WIDTH-1:0] wr_lite_data_q, wr_lite_data_d;
  logic [STRB_WIDTH-1:0] wr_lite_strb_q, wr_lite_strb_d;
  logic wr_error_q, wr_error_d;
  logic wr_apb_last_q, wr_apb_last_d;

  rd_state_e rd_state_q, rd_state_d;
  src_e rd_src_q, rd_src_d;
  route_e rd_route_q, rd_route_d;
  logic [ID_WIDTH-1:0] rd_id_q, rd_id_d;
  logic [ADDR_WIDTH-1:0] rd_addr_q, rd_addr_d;
  logic [7:0] rd_len_q, rd_len_d;
  logic [2:0] rd_size_q, rd_size_d;
  logic [1:0] rd_burst_q, rd_burst_d;
  logic rd_lock_q, rd_lock_d;
  logic [3:0] rd_cache_q, rd_cache_d;
  logic [2:0] rd_prot_q, rd_prot_d;
  logic [3:0] rd_qos_q, rd_qos_d;
  logic [8:0] rd_beats_left_q, rd_beats_left_d;
  logic [DATA_WIDTH-1:0] rd_data_q, rd_data_d;
  logic [1:0] rd_resp_q, rd_resp_d;

  apb_state_e apb_state_q, apb_state_d;
  apb_grant_e apb_grant_q, apb_grant_d;
  logic [ADDR_WIDTH-1:0] apb_addr_q, apb_addr_d;
  logic [2:0] apb_prot_q, apb_prot_d;
  logic apb_write_q, apb_write_d;
  logic [DATA_WIDTH-1:0] apb_wdata_q, apb_wdata_d;
  logic [STRB_WIDTH-1:0] apb_wstrb_q, apb_wstrb_d;
  logic [DATA_WIDTH-1:0] apb_rdata_q, apb_rdata_d;
  logic apb_error_q, apb_error_d;

  logic start_axi_wr;
  logic start_axil_wr;
  logic start_axi_rd;
  logic start_axil_rd;
  logic wr_resp_ready;
  logic rd_resp_ready;
  logic wr_apb_req_valid;
  logic [ADDR_WIDTH-1:0] wr_apb_req_addr;
  logic [2:0] wr_apb_req_prot;
  logic [DATA_WIDTH-1:0] wr_apb_req_data;
  logic [STRB_WIDTH-1:0] wr_apb_req_strb;
  logic wr_apb_rsp_ready;
  logic rd_apb_req_valid;
  logic [ADDR_WIDTH-1:0] rd_apb_req_addr;
  logic [2:0] rd_apb_req_prot;
  logic rd_apb_rsp_ready;

  always_comb begin
    axil_aw_valid_d = axil_aw_valid_q;
    axil_awaddr_d = axil_awaddr_q;
    axil_awprot_d = axil_awprot_q;
    axil_w_valid_d = axil_w_valid_q;
    axil_wdata_d = axil_wdata_q;
    axil_wstrb_d = axil_wstrb_q;
    axil_ar_valid_d = axil_ar_valid_q;
    axil_araddr_d = axil_araddr_q;
    axil_arprot_d = axil_arprot_q;

    wr_state_d = wr_state_q;
    wr_src_d = wr_src_q;
    wr_route_d = wr_route_q;
    wr_id_d = wr_id_q;
    wr_addr_d = wr_addr_q;
    wr_len_d = wr_len_q;
    wr_size_d = wr_size_q;
    wr_burst_d = wr_burst_q;
    wr_lock_d = wr_lock_q;
    wr_cache_d = wr_cache_q;
    wr_prot_d = wr_prot_q;
    wr_qos_d = wr_qos_q;
    wr_beats_left_d = wr_beats_left_q;
    wr_lite_data_d = wr_lite_data_q;
    wr_lite_strb_d = wr_lite_strb_q;
    wr_error_d = wr_error_q;
    wr_apb_last_d = wr_apb_last_q;

    rd_state_d = rd_state_q;
    rd_src_d = rd_src_q;
    rd_route_d = rd_route_q;
    rd_id_d = rd_id_q;
    rd_addr_d = rd_addr_q;
    rd_len_d = rd_len_q;
    rd_size_d = rd_size_q;
    rd_burst_d = rd_burst_q;
    rd_lock_d = rd_lock_q;
    rd_cache_d = rd_cache_q;
    rd_prot_d = rd_prot_q;
    rd_qos_d = rd_qos_q;
    rd_beats_left_d = rd_beats_left_q;
    rd_data_d = rd_data_q;
    rd_resp_d = rd_resp_q;

    apb_state_d = apb_state_q;
    apb_grant_d = apb_grant_q;
    apb_addr_d = apb_addr_q;
    apb_prot_d = apb_prot_q;
    apb_write_d = apb_write_q;
    apb_wdata_d = apb_wdata_q;
    apb_wstrb_d = apb_wstrb_q;
    apb_rdata_d = apb_rdata_q;
    apb_error_d = apb_error_q;

    s_axi_awready = 1'b0;
    s_axi_wready = 1'b0;
    s_axi_bid = wr_id_q;
    s_axi_bresp = RESP_OKAY;
    s_axi_bvalid = 1'b0;
    s_axi_arready = 1'b0;
    s_axi_rid = rd_id_q;
    s_axi_rdata = '0;
    s_axi_rresp = RESP_OKAY;
    s_axi_rlast = 1'b0;
    s_axi_rvalid = 1'b0;

    s_axil_awready = !axil_aw_valid_q;
    s_axil_wready = !axil_w_valid_q;
    s_axil_bresp = RESP_OKAY;
    s_axil_bvalid = 1'b0;
    s_axil_arready = !axil_ar_valid_q;
    s_axil_rdata = '0;
    s_axil_rresp = RESP_OKAY;
    s_axil_rvalid = 1'b0;

    m_axi_awid = wr_id_q;
    m_axi_awaddr = wr_addr_q;
    m_axi_awlen = wr_len_q;
    m_axi_awsize = wr_size_q;
    m_axi_awburst = wr_burst_q;
    m_axi_awlock = wr_lock_q;
    m_axi_awcache = wr_cache_q;
    m_axi_awprot = wr_prot_q;
    m_axi_awqos = wr_qos_q;
    m_axi_awvalid = 1'b0;
    m_axi_wdata = (wr_src_q == SRC_AXIL) ? wr_lite_data_q : s_axi_wdata;
    m_axi_wstrb = (wr_src_q == SRC_AXIL) ? wr_lite_strb_q : s_axi_wstrb;
    m_axi_wlast = (wr_src_q == SRC_AXIL) ? 1'b1 : s_axi_wlast;
    m_axi_wvalid = 1'b0;
    m_axi_bready = 1'b0;
    m_axi_arid = rd_id_q;
    m_axi_araddr = rd_addr_q;
    m_axi_arlen = rd_len_q;
    m_axi_arsize = rd_size_q;
    m_axi_arburst = rd_burst_q;
    m_axi_arlock = rd_lock_q;
    m_axi_arcache = rd_cache_q;
    m_axi_arprot = rd_prot_q;
    m_axi_arqos = rd_qos_q;
    m_axi_arvalid = 1'b0;
    m_axi_rready = 1'b0;

    wr_apb_req_valid = 1'b0;
    wr_apb_req_addr = wr_addr_q;
    wr_apb_req_prot = wr_prot_q;
    wr_apb_req_data = (wr_src_q == SRC_AXIL) ? wr_lite_data_q : s_axi_wdata;
    wr_apb_req_strb = (wr_src_q == SRC_AXIL) ? wr_lite_strb_q : s_axi_wstrb;
    wr_apb_rsp_ready = 1'b0;
    rd_apb_req_valid = 1'b0;
    rd_apb_req_addr = rd_addr_q;
    rd_apb_req_prot = rd_prot_q;
    rd_apb_rsp_ready = 1'b0;

    m_apb_paddr = apb_addr_q;
    m_apb_pprot = apb_prot_q;
    m_apb_psel = (apb_state_q == APB_SETUP) || (apb_state_q == APB_ACCESS);
    m_apb_penable = (apb_state_q == APB_ACCESS);
    m_apb_pwrite = apb_write_q;
    m_apb_pwdata = apb_wdata_q;
    m_apb_pstrb = apb_write_q ? apb_wstrb_q : '0;

    start_axil_wr = (wr_state_q == WR_IDLE) && axil_aw_valid_q && axil_w_valid_q;
    start_axi_wr = (wr_state_q == WR_IDLE) && s_axi_awvalid && !start_axil_wr;
    start_axil_rd = (rd_state_q == RD_IDLE) && axil_ar_valid_q;
    start_axi_rd = (rd_state_q == RD_IDLE) && s_axi_arvalid && !start_axil_rd;
    wr_resp_ready = (wr_src_q == SRC_AXIL) ? s_axil_bready : s_axi_bready;
    rd_resp_ready = (rd_src_q == SRC_AXIL) ? s_axil_rready : s_axi_rready;

    if (s_axil_awready && s_axil_awvalid) begin
      axil_aw_valid_d = 1'b1;
      axil_awaddr_d = s_axil_awaddr;
      axil_awprot_d = s_axil_awprot;
    end

    if (s_axil_wready && s_axil_wvalid) begin
      axil_w_valid_d = 1'b1;
      axil_wdata_d = s_axil_wdata;
      axil_wstrb_d = s_axil_wstrb;
    end

    if (s_axil_arready && s_axil_arvalid) begin
      axil_ar_valid_d = 1'b1;
      axil_araddr_d = s_axil_araddr;
      axil_arprot_d = s_axil_arprot;
    end

    unique case (wr_state_q)
      WR_IDLE: begin
        if (start_axil_wr) begin
          axil_aw_valid_d = 1'b0;
          axil_w_valid_d = 1'b0;
          wr_src_d = SRC_AXIL;
          wr_route_d = decode_route(axil_awaddr_q);
          wr_id_d = '0;
          wr_addr_d = axil_awaddr_q;
          wr_len_d = 8'h00;
          wr_size_d = AXIL_SIZE;
          wr_burst_d = 2'b01;
          wr_lock_d = 1'b0;
          wr_cache_d = 4'h0;
          wr_prot_d = axil_awprot_q;
          wr_qos_d = 4'h0;
          wr_beats_left_d = 9'd1;
          wr_lite_data_d = axil_wdata_q;
          wr_lite_strb_d = axil_wstrb_q;
          wr_error_d = 1'b0;
          if (decode_route(axil_awaddr_q) == ROUTE_AXI) begin
            wr_state_d = WR_AXI_AW;
          end else if (decode_route(axil_awaddr_q) == ROUTE_APB) begin
            wr_state_d = WR_APB_W;
          end else begin
            wr_error_d = 1'b1;
            wr_state_d = WR_RESP;
          end
        end else if (start_axi_wr) begin
          s_axi_awready = 1'b1;
          wr_src_d = SRC_AXI;
          wr_route_d = decode_route(s_axi_awaddr);
          wr_id_d = s_axi_awid;
          wr_addr_d = s_axi_awaddr;
          wr_len_d = s_axi_awlen;
          wr_size_d = s_axi_awsize;
          wr_burst_d = s_axi_awburst;
          wr_lock_d = s_axi_awlock;
          wr_cache_d = s_axi_awcache;
          wr_prot_d = s_axi_awprot;
          wr_qos_d = s_axi_awqos;
          wr_beats_left_d = {1'b0, s_axi_awlen} + 9'd1;
          wr_error_d = 1'b0;
          if (decode_route(s_axi_awaddr) == ROUTE_AXI) begin
            wr_state_d = WR_AXI_AW;
          end else if (decode_route(s_axi_awaddr) == ROUTE_APB) begin
            wr_state_d = WR_APB_W;
          end else begin
            wr_error_d = 1'b1;
            wr_state_d = WR_ERR_W;
          end
        end
      end

      WR_AXI_AW: begin
        m_axi_awvalid = 1'b1;
        if (m_axi_awready) begin
          wr_state_d = WR_AXI_W;
        end
      end

      WR_AXI_W: begin
        m_axi_wvalid = (wr_src_q == SRC_AXIL) ? 1'b1 : s_axi_wvalid;
        s_axi_wready = (wr_src_q == SRC_AXI) ? m_axi_wready : 1'b0;
        if (m_axi_wvalid && m_axi_wready) begin
          wr_beats_left_d = wr_beats_left_q - 9'd1;
          if ((wr_src_q == SRC_AXIL) || s_axi_wlast || (wr_beats_left_q == 9'd1)) begin
            wr_state_d = WR_AXI_B;
          end
        end
      end

      WR_AXI_B: begin
        if (wr_src_q == SRC_AXIL) begin
          s_axil_bvalid = m_axi_bvalid;
          s_axil_bresp = m_axi_bresp;
          m_axi_bready = s_axil_bready;
        end else begin
          s_axi_bvalid = m_axi_bvalid;
          s_axi_bid = m_axi_bid;
          s_axi_bresp = m_axi_bresp;
          m_axi_bready = s_axi_bready;
        end
        if (m_axi_bvalid && m_axi_bready) begin
          wr_state_d = WR_IDLE;
        end
      end

      WR_APB_W: begin
        wr_apb_req_valid = (wr_src_q == SRC_AXIL) ? 1'b1 : s_axi_wvalid;
        s_axi_wready = ((wr_src_q == SRC_AXI) && (apb_state_q == APB_IDLE));
        if (wr_apb_req_valid && (apb_state_q == APB_IDLE)) begin
          wr_apb_last_d = (wr_src_q == SRC_AXIL) || s_axi_wlast || (wr_beats_left_q == 9'd1);
          wr_state_d = WR_APB_RSP;
        end
      end

      WR_APB_RSP: begin
        wr_apb_rsp_ready = 1'b1;
        if ((apb_state_q == APB_RESP) && (apb_grant_q == APB_GRANT_WR)) begin
          wr_error_d = wr_error_q || apb_error_q;
          wr_beats_left_d = wr_beats_left_q - 9'd1;
          if (wr_apb_last_q) begin
            wr_state_d = WR_RESP;
          end else begin
            wr_addr_d = next_burst_addr(wr_addr_q, wr_size_q, wr_burst_q);
            wr_state_d = WR_APB_W;
          end
        end
      end

      WR_ERR_W: begin
        s_axi_wready = 1'b1;
        if (s_axi_wvalid) begin
          wr_beats_left_d = wr_beats_left_q - 9'd1;
          if (s_axi_wlast || (wr_beats_left_q == 9'd1)) begin
            wr_state_d = WR_RESP;
          end
        end
      end

      WR_RESP: begin
        if (wr_src_q == SRC_AXIL) begin
          s_axil_bvalid = 1'b1;
          s_axil_bresp = (wr_route_q == ROUTE_ERR) ? RESP_DECERR :
                         wr_error_q ? RESP_SLVERR : RESP_OKAY;
        end else begin
          s_axi_bvalid = 1'b1;
          s_axi_bid = wr_id_q;
          s_axi_bresp = (wr_route_q == ROUTE_ERR) ? RESP_DECERR :
                        wr_error_q ? RESP_SLVERR : RESP_OKAY;
        end
        if (wr_resp_ready) begin
          wr_state_d = WR_IDLE;
        end
      end

      default: begin
        wr_state_d = WR_IDLE;
      end
    endcase

    unique case (rd_state_q)
      RD_IDLE: begin
        if (start_axil_rd) begin
          axil_ar_valid_d = 1'b0;
          rd_src_d = SRC_AXIL;
          rd_route_d = decode_route(axil_araddr_q);
          rd_id_d = '0;
          rd_addr_d = axil_araddr_q;
          rd_len_d = 8'h00;
          rd_size_d = AXIL_SIZE;
          rd_burst_d = 2'b01;
          rd_lock_d = 1'b0;
          rd_cache_d = 4'h0;
          rd_prot_d = axil_arprot_q;
          rd_qos_d = 4'h0;
          rd_beats_left_d = 9'd1;
          if (decode_route(axil_araddr_q) == ROUTE_AXI) begin
            rd_state_d = RD_AXI_AR;
          end else if (decode_route(axil_araddr_q) == ROUTE_APB) begin
            rd_state_d = RD_APB_REQ;
          end else begin
            rd_resp_d = RESP_DECERR;
            rd_data_d = '0;
            rd_state_d = RD_ERR_SEND;
          end
        end else if (start_axi_rd) begin
          s_axi_arready = 1'b1;
          rd_src_d = SRC_AXI;
          rd_route_d = decode_route(s_axi_araddr);
          rd_id_d = s_axi_arid;
          rd_addr_d = s_axi_araddr;
          rd_len_d = s_axi_arlen;
          rd_size_d = s_axi_arsize;
          rd_burst_d = s_axi_arburst;
          rd_lock_d = s_axi_arlock;
          rd_cache_d = s_axi_arcache;
          rd_prot_d = s_axi_arprot;
          rd_qos_d = s_axi_arqos;
          rd_beats_left_d = {1'b0, s_axi_arlen} + 9'd1;
          if (decode_route(s_axi_araddr) == ROUTE_AXI) begin
            rd_state_d = RD_AXI_AR;
          end else if (decode_route(s_axi_araddr) == ROUTE_APB) begin
            rd_state_d = RD_APB_REQ;
          end else begin
            rd_resp_d = RESP_DECERR;
            rd_data_d = '0;
            rd_state_d = RD_ERR_SEND;
          end
        end
      end

      RD_AXI_AR: begin
        m_axi_arvalid = 1'b1;
        if (m_axi_arready) begin
          rd_state_d = RD_AXI_R;
        end
      end

      RD_AXI_R: begin
        if (rd_src_q == SRC_AXIL) begin
          s_axil_rvalid = m_axi_rvalid;
          s_axil_rdata = m_axi_rdata;
          s_axil_rresp = m_axi_rresp;
          m_axi_rready = s_axil_rready;
        end else begin
          s_axi_rvalid = m_axi_rvalid;
          s_axi_rid = m_axi_rid;
          s_axi_rdata = m_axi_rdata;
          s_axi_rresp = m_axi_rresp;
          s_axi_rlast = m_axi_rlast;
          m_axi_rready = s_axi_rready;
        end
        if (m_axi_rvalid && m_axi_rready &&
            ((rd_src_q == SRC_AXIL) || m_axi_rlast)) begin
          rd_state_d = RD_IDLE;
        end
      end

      RD_APB_REQ: begin
        rd_apb_req_valid = 1'b1;
        if ((apb_state_q == APB_IDLE) && !wr_apb_req_valid) begin
          rd_state_d = RD_APB_RSP;
        end
      end

      RD_APB_RSP: begin
        rd_apb_rsp_ready = 1'b1;
        if ((apb_state_q == APB_RESP) && (apb_grant_q == APB_GRANT_RD)) begin
          rd_data_d = apb_rdata_q;
          rd_resp_d = apb_error_q ? RESP_SLVERR : RESP_OKAY;
          rd_state_d = RD_SEND;
        end
      end

      RD_SEND: begin
        if (rd_src_q == SRC_AXIL) begin
          s_axil_rvalid = 1'b1;
          s_axil_rdata = rd_data_q;
          s_axil_rresp = rd_resp_q;
        end else begin
          s_axi_rvalid = 1'b1;
          s_axi_rid = rd_id_q;
          s_axi_rdata = rd_data_q;
          s_axi_rresp = rd_resp_q;
          s_axi_rlast = (rd_beats_left_q == 9'd1);
        end
        if (rd_resp_ready) begin
          rd_beats_left_d = rd_beats_left_q - 9'd1;
          if ((rd_src_q == SRC_AXIL) || (rd_beats_left_q == 9'd1)) begin
            rd_state_d = RD_IDLE;
          end else begin
            rd_addr_d = next_burst_addr(rd_addr_q, rd_size_q, rd_burst_q);
            rd_state_d = RD_APB_REQ;
          end
        end
      end

      RD_ERR_SEND: begin
        if (rd_src_q == SRC_AXIL) begin
          s_axil_rvalid = 1'b1;
          s_axil_rdata = '0;
          s_axil_rresp = rd_resp_q;
        end else begin
          s_axi_rvalid = 1'b1;
          s_axi_rid = rd_id_q;
          s_axi_rdata = '0;
          s_axi_rresp = rd_resp_q;
          s_axi_rlast = (rd_beats_left_q == 9'd1);
        end
        if (rd_resp_ready) begin
          rd_beats_left_d = rd_beats_left_q - 9'd1;
          if ((rd_src_q == SRC_AXIL) || (rd_beats_left_q == 9'd1)) begin
            rd_state_d = RD_IDLE;
          end
        end
      end

      default: begin
        rd_state_d = RD_IDLE;
      end
    endcase

    unique case (apb_state_q)
      APB_IDLE: begin
        if (wr_apb_req_valid) begin
          apb_grant_d = APB_GRANT_WR;
          apb_addr_d = wr_apb_req_addr;
          apb_prot_d = wr_apb_req_prot;
          apb_write_d = 1'b1;
          apb_wdata_d = wr_apb_req_data;
          apb_wstrb_d = wr_apb_req_strb;
          apb_state_d = APB_SETUP;
        end else if (rd_apb_req_valid) begin
          apb_grant_d = APB_GRANT_RD;
          apb_addr_d = rd_apb_req_addr;
          apb_prot_d = rd_apb_req_prot;
          apb_write_d = 1'b0;
          apb_wdata_d = '0;
          apb_wstrb_d = '0;
          apb_state_d = APB_SETUP;
        end
      end

      APB_SETUP: begin
        apb_state_d = APB_ACCESS;
      end

      APB_ACCESS: begin
        if (m_apb_pready) begin
          apb_rdata_d = m_apb_prdata;
          apb_error_d = m_apb_pslverr;
          apb_state_d = APB_RESP;
        end
      end

      APB_RESP: begin
        if (apb_grant_q == APB_GRANT_WR) begin
          if (wr_apb_rsp_ready) begin
            apb_state_d = APB_IDLE;
          end
        end else begin
          if (rd_apb_rsp_ready) begin
            apb_state_d = APB_IDLE;
          end
        end
      end

      default: begin
        apb_state_d = APB_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axil_aw_valid_q <= 1'b0;
      axil_awaddr_q <= '0;
      axil_awprot_q <= '0;
      axil_w_valid_q <= 1'b0;
      axil_wdata_q <= '0;
      axil_wstrb_q <= '0;
      axil_ar_valid_q <= 1'b0;
      axil_araddr_q <= '0;
      axil_arprot_q <= '0;
      wr_state_q <= WR_IDLE;
      wr_src_q <= SRC_AXI;
      wr_route_q <= ROUTE_ERR;
      wr_id_q <= '0;
      wr_addr_q <= '0;
      wr_len_q <= '0;
      wr_size_q <= '0;
      wr_burst_q <= '0;
      wr_lock_q <= 1'b0;
      wr_cache_q <= '0;
      wr_prot_q <= '0;
      wr_qos_q <= '0;
      wr_beats_left_q <= '0;
      wr_lite_data_q <= '0;
      wr_lite_strb_q <= '0;
      wr_error_q <= 1'b0;
      wr_apb_last_q <= 1'b0;
      rd_state_q <= RD_IDLE;
      rd_src_q <= SRC_AXI;
      rd_route_q <= ROUTE_ERR;
      rd_id_q <= '0;
      rd_addr_q <= '0;
      rd_len_q <= '0;
      rd_size_q <= '0;
      rd_burst_q <= '0;
      rd_lock_q <= 1'b0;
      rd_cache_q <= '0;
      rd_prot_q <= '0;
      rd_qos_q <= '0;
      rd_beats_left_q <= '0;
      rd_data_q <= '0;
      rd_resp_q <= RESP_OKAY;
      apb_state_q <= APB_IDLE;
      apb_grant_q <= APB_GRANT_WR;
      apb_addr_q <= '0;
      apb_prot_q <= '0;
      apb_write_q <= 1'b0;
      apb_wdata_q <= '0;
      apb_wstrb_q <= '0;
      apb_rdata_q <= '0;
      apb_error_q <= 1'b0;
    end else begin
      axil_aw_valid_q <= axil_aw_valid_d;
      axil_awaddr_q <= axil_awaddr_d;
      axil_awprot_q <= axil_awprot_d;
      axil_w_valid_q <= axil_w_valid_d;
      axil_wdata_q <= axil_wdata_d;
      axil_wstrb_q <= axil_wstrb_d;
      axil_ar_valid_q <= axil_ar_valid_d;
      axil_araddr_q <= axil_araddr_d;
      axil_arprot_q <= axil_arprot_d;
      wr_state_q <= wr_state_d;
      wr_src_q <= wr_src_d;
      wr_route_q <= wr_route_d;
      wr_id_q <= wr_id_d;
      wr_addr_q <= wr_addr_d;
      wr_len_q <= wr_len_d;
      wr_size_q <= wr_size_d;
      wr_burst_q <= wr_burst_d;
      wr_lock_q <= wr_lock_d;
      wr_cache_q <= wr_cache_d;
      wr_prot_q <= wr_prot_d;
      wr_qos_q <= wr_qos_d;
      wr_beats_left_q <= wr_beats_left_d;
      wr_lite_data_q <= wr_lite_data_d;
      wr_lite_strb_q <= wr_lite_strb_d;
      wr_error_q <= wr_error_d;
      wr_apb_last_q <= wr_apb_last_d;
      rd_state_q <= rd_state_d;
      rd_src_q <= rd_src_d;
      rd_route_q <= rd_route_d;
      rd_id_q <= rd_id_d;
      rd_addr_q <= rd_addr_d;
      rd_len_q <= rd_len_d;
      rd_size_q <= rd_size_d;
      rd_burst_q <= rd_burst_d;
      rd_lock_q <= rd_lock_d;
      rd_cache_q <= rd_cache_d;
      rd_prot_q <= rd_prot_d;
      rd_qos_q <= rd_qos_d;
      rd_beats_left_q <= rd_beats_left_d;
      rd_data_q <= rd_data_d;
      rd_resp_q <= rd_resp_d;
      apb_state_q <= apb_state_d;
      apb_grant_q <= apb_grant_d;
      apb_addr_q <= apb_addr_d;
      apb_prot_q <= apb_prot_d;
      apb_write_q <= apb_write_d;
      apb_wdata_q <= apb_wdata_d;
      apb_wstrb_q <= apb_wstrb_d;
      apb_rdata_q <= apb_rdata_d;
      apb_error_q <= apb_error_d;
    end
  end
endmodule

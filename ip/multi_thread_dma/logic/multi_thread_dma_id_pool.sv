`timescale 1ns/1ps

module multi_thread_dma_id_pool #(
  parameter int SLOT_COUNT = 8,
  parameter int ID_WIDTH = (SLOT_COUNT <= 1) ? 1 : $clog2(SLOT_COUNT)
) (
  input  logic                clk,
  input  logic                rst_n,
  input  logic                clear,

  output logic                alloc_valid,
  output logic [ID_WIDTH-1:0] alloc_id,
  input  logic                alloc_fire,

  input  logic                free_valid,
  input  logic [ID_WIDTH-1:0] free_id
);
  logic [SLOT_COUNT-1:0] in_use_q, in_use_d;

  always_comb begin
    alloc_valid = 1'b0;
    alloc_id = '0;

    for (int slot = 0; slot < SLOT_COUNT; slot++) begin
      if (!alloc_valid && !in_use_q[slot]) begin
        alloc_valid = 1'b1;
        alloc_id = ID_WIDTH'(slot);
      end
    end
  end

  always_comb begin
    in_use_d = in_use_q;

    if (clear) begin
      in_use_d = '0;
    end else begin
      if (free_valid) begin
        in_use_d[free_id] = 1'b0;
      end
      if (alloc_fire) begin
        in_use_d[alloc_id] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_use_q <= '0;
    end else begin
      in_use_q <= in_use_d;
    end
  end

`ifndef SYNTHESIS
  default clocking id_pool_cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  assert_alloc_uses_free_id:
    assert property (alloc_fire |-> !in_use_q[alloc_id])
    else $error("multi_thread_dma ID pool allocated an ID already in use");

  assert_free_uses_busy_id:
    assert property (free_valid |-> in_use_q[free_id])
    else $error("multi_thread_dma ID pool freed an ID that was not in use");
`endif
endmodule

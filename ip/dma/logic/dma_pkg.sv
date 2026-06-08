`timescale 1ns/1ps

package dma_pkg;
  typedef enum logic [1:0] {
    DMA_SLOT_FREE,
    DMA_SLOT_READ_OUTSTANDING,
    DMA_SLOT_WRITE_PENDING,
    DMA_SLOT_WRITE_OUTSTANDING
  } dma_slot_state_e;
endpackage

`timescale 1ns/1ps

module riscv32im_scoreboard (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         issue_stage_i,
  input  logic                         issue_fire_i,
  input  riscv32im_issue_info_t        issue_i,
  input  riscv32im_engine_busy_t       engines_i,
  input  riscv32im_retire_info_t       retire_i,
  output riscv32im_scoreboard_status_t status_o
);
  logic [31:0] reg_busy_q;
  logic [3:0]  outstanding_q;
  logic        control_busy_q;

  logic raw_hazard;
  logic waw_hazard;
  logic serial_hazard;
  logic engine_hazard;

  assign raw_hazard = ((issue_i.uses_rs1 && (issue_i.rs1 != 5'd0) && reg_busy_q[issue_i.rs1]) ||
                       (issue_i.uses_rs2 && (issue_i.rs2 != 5'd0) && reg_busy_q[issue_i.rs2]));
  assign waw_hazard = issue_i.writes_rd && (issue_i.rd != 5'd0) && reg_busy_q[issue_i.rd];
  assign serial_hazard = issue_i.serial && (outstanding_q != 4'd0);
  assign engine_hazard = (issue_i.to_alu && engines_i.alu_busy) ||
                         (issue_i.to_muldiv && engines_i.muldiv_busy) ||
                         (issue_i.to_lsu && engines_i.lsu_busy);

  assign status_o.issue_allowed = issue_stage_i &&
                                  !control_busy_q &&
                                  !raw_hazard &&
                                  !waw_hazard &&
                                  !serial_hazard &&
                                  !engine_hazard;
  assign status_o.raw_hazard = raw_hazard;
  assign status_o.waw_hazard = waw_hazard;
  assign status_o.serial_hazard = serial_hazard;
  assign status_o.engine_hazard = engine_hazard;
  assign status_o.control_busy = control_busy_q;
  assign status_o.outstanding = outstanding_q;
  assign status_o.reg_busy = reg_busy_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_busy_q <= 32'h0000_0000;
      outstanding_q <= 4'd0;
      control_busy_q <= 1'b0;
    end else begin
      if (retire_i.valid && retire_i.writes_rd && (retire_i.rd != 5'd0)) begin
        reg_busy_q[retire_i.rd] <= 1'b0;
      end

      if (issue_fire_i && issue_i.writes_rd && (issue_i.rd != 5'd0)) begin
        reg_busy_q[issue_i.rd] <= 1'b1;
      end

      if (issue_fire_i && !retire_i.valid) begin
        outstanding_q <= outstanding_q + 4'd1;
      end else if (!issue_fire_i && retire_i.valid) begin
        outstanding_q <= outstanding_q - 4'd1;
      end

      if (retire_i.flush_control || retire_i.control_retired) begin
        control_busy_q <= 1'b0;
      end else if (issue_fire_i && issue_i.serial) begin
        control_busy_q <= 1'b1;
      end
    end
  end
endmodule

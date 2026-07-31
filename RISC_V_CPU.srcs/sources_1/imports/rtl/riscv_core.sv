// ============================================================================
// Module : riscv_core
// Project: RISC-V 2-Issue Superscalar Processor (Optimized)
// Description: Top-level CPU core module integrating all pipeline stages.
//              - Optimizations: dual-port dmem, RAS, 128-entry 2-way BTB
//              - Instantiates: fetch, decode, execute, memory, writeback units
//              - Manages pipeline registers: IF/ID, ID/EX, EX/MEM, MEM/WB
//              - Each pipeline register carries dual-lane (2-wide) data
//              - Handles global stall/flush signal distribution
//              - Harvard architecture: separate instruction and data ports
// ============================================================================

`include "defines.sv"
`include "types.sv"

module riscv_core (
    input  logic        clk,            // System clock
    input  logic        rst_n,          // Synchronous reset, active low

    // ----- Instruction Memory Interface (Harvard, 64-bit read) -----
    output logic [31:0] imem_addr,      // Instruction memory address
    input  logic [63:0] imem_rdata,     // 64-bit instruction data (2 instructions)

    // ----- Data Memory Port 0 (Lane 0, 32-bit read/write) -----
    output logic [31:0] dmem_addr0,     // Lane 0 data memory address
    output logic [31:0] dmem_wdata0,    // Lane 0 data memory write data
    output logic        dmem_we0,       // Lane 0 data memory write enable
    output logic [3:0]  dmem_be0,       // Lane 0 data memory byte enable
    input  logic [31:0] dmem_rdata0,    // Lane 0 data memory read data

    // ----- Data Memory Port 1 (Lane 1, 32-bit read/write) -----
    output logic [31:0] dmem_addr1,     // Lane 1 data memory address
    output logic [31:0] dmem_wdata1,    // Lane 1 data memory write data
    output logic        dmem_we1,       // Lane 1 data memory write enable
    output logic [3:0]  dmem_be1,       // Lane 1 data memory byte enable
    input  logic [31:0] dmem_rdata1     // Lane 1 data memory read data
);

    // ========================================================================
    // Pipeline Registers
    // ========================================================================
    if_id_reg_t  if_id_reg,  if_id_reg_next;
    id_ex_reg_t  id_ex_reg,  id_ex_reg_next;
    ex_mem_reg_t ex_mem_reg, ex_mem_reg_next;
    mem_wb_reg_t mem_wb_reg, mem_wb_reg_next;

    // ========================================================================
    // Global Control Signals
    // ========================================================================
    logic stall;              // Pipeline stall (hazard detected)
    logic flush_if_id;        // Flush IF/ID register (branch mispredict)
    logic flush_id_ex;        // Flush ID/EX register (stall or mispredict)
    logic stall_fetch;        // Stall instruction fetch

    // Branch resolution signals (from execute stage)
    logic        branch_resolve;
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        branch_mispredict;
    logic [31:0] branch_correct_pc;

    // Branch predictor interface signals
    logic [31:0] bp_pc;
    logic        bp_hit;
    logic        bp_taken;
    logic [31:0] bp_target;

    // Branch predictor pre-decode signals (from fetch_unit)
    logic        pre_is_jal;
    logic        pre_is_jalr;
    logic [31:0] pre_jal_target;

    // Branch predictor update signals
    logic        bp_update_valid;
    logic [31:0] bp_update_pc;
    logic        bp_update_taken;
    logic [31:0] bp_update_target;
    logic [1:0]  bp_update_br_type;

    // RAS flush signal (on branch mispredict)
    logic        ras_flush;

    // Register file read addresses (from decode unit)
    logic [4:0]  rf_rs1_addr0, rf_rs2_addr0;
    logic [4:0]  rf_rs1_addr1, rf_rs2_addr1;

    // Register file read data
    logic [31:0] rf_rs1_data0, rf_rs2_data0;
    logic [31:0] rf_rs1_data1, rf_rs2_data1;

    // Register file write signals (from writeback unit)
    logic [4:0]  rf_waddr0, rf_waddr1;
    logic [31:0] rf_wdata0, rf_wdata1;
    logic        rf_we0, rf_we1;

    // ========================================================================
    // Module Instantiation: Branch Predictor
    // ========================================================================
    branch_predictor u_branch_predictor (
        .clk            (clk),
        .rst_n          (rst_n),
        .pc             (bp_pc),
        .bp_hit         (bp_hit),
        .bp_taken       (bp_taken),
        .bp_target      (bp_target),
        .pre_is_jal     (pre_is_jal),
        .pre_is_jalr    (pre_is_jalr),
        .pre_jal_target (pre_jal_target),
        .update_valid   (bp_update_valid),
        .update_pc      (bp_update_pc),
        .update_taken   (bp_update_taken),
        .update_target  (bp_update_target),
        .update_br_type (bp_update_br_type),
        .ras_flush      (ras_flush)
    );

    // ========================================================================
    // Module Instantiation: Fetch Unit
    // ========================================================================
    fetch_unit u_fetch_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .imem_addr          (imem_addr),
        .imem_rdata         (imem_rdata),
        .bp_pc              (bp_pc),
        .bp_hit             (bp_hit),
        .bp_taken           (bp_taken),
        .bp_target          (bp_target),
        .stall              (stall_fetch),
        .flush              (flush_if_id),
        .branch_resolve     (branch_resolve),
        .branch_mispredict  (branch_mispredict),
        .branch_correct_pc  (branch_correct_pc),
        .fetch_pc0          (if_id_reg_next.pc0),
        .fetch_pc1          (if_id_reg_next.pc1),
        .fetch_inst0        (if_id_reg_next.inst0),
        .fetch_inst1        (if_id_reg_next.inst1),
        .fetch_valid0       (if_id_reg_next.valid0),
        .fetch_valid1       (if_id_reg_next.valid1),
        .fetch_bp_taken0    (if_id_reg_next.bp_taken0),
        .fetch_bp_target0   (if_id_reg_next.bp_target0),
        .pre_is_jal         (pre_is_jal),
        .pre_is_jalr        (pre_is_jalr),
        .pre_jal_target     (pre_jal_target)
    );

    // ========================================================================
    // Module Instantiation: Register File (4 read ports, 2 write ports)
    // ========================================================================
    regfile u_regfile (
        .clk    (clk),
        .rst_n  (rst_n),
        // Read ports
        .raddr0 (rf_rs1_addr0),     // Lane 0 rs1
        .rdata0 (rf_rs1_data0),
        .raddr1 (rf_rs2_addr0),     // Lane 0 rs2
        .rdata1 (rf_rs2_data0),
        .raddr2 (rf_rs1_addr1),     // Lane 1 rs1
        .rdata2 (rf_rs1_data1),
        .raddr3 (rf_rs2_addr1),     // Lane 1 rs2
        .rdata3 (rf_rs2_data1),
        // Write ports
        .waddr0 (rf_waddr0),        // Lane 0 writeback
        .wdata0 (rf_wdata0),
        .we0    (rf_we0),
        .waddr1 (rf_waddr1),        // Lane 1 writeback
        .wdata1 (rf_wdata1),
        .we1    (rf_we1)
    );

    // ========================================================================
    // Module Instantiation: Decode Unit
    // ========================================================================
    decode_unit u_decode_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        // IF/ID inputs
        .id_pc0         (if_id_reg.pc0),
        .id_inst0       (if_id_reg.inst0),
        .id_valid0      (if_id_reg.valid0),
        .id_pc1         (if_id_reg.pc1),
        .id_inst1       (if_id_reg.inst1),
        .id_valid1      (if_id_reg.valid1),
        .id_bp_taken0   (if_id_reg.bp_taken0),
        .id_bp_target0  (if_id_reg.bp_target0),
        // Register file read data
        .rf_rs1_data0   (rf_rs1_data0),
        .rf_rs2_data0   (rf_rs2_data0),
        .rf_rs1_data1   (rf_rs1_data1),
        .rf_rs2_data1   (rf_rs2_data1),
        // Register file read addresses
        .rf_rs1_addr0   (rf_rs1_addr0),
        .rf_rs2_addr0   (rf_rs2_addr0),
        .rf_rs1_addr1   (rf_rs1_addr1),
        .rf_rs2_addr1   (rf_rs2_addr1),
        // ID/EX output
        .id_ex_out      (id_ex_reg_next)
    );

    // ========================================================================
    // Module Instantiation: Hazard Unit
    // ========================================================================
    hazard_unit u_hazard_unit (
        // ID stage info
        .id_rd_addr0        (id_ex_reg_next.rd_addr0),
        .id_reg_write0      (id_ex_reg_next.reg_write0),
        .id_valid0          (id_ex_reg_next.valid0),
        .id_rd_addr1        (id_ex_reg_next.rd_addr1),
        .id_reg_write1      (id_ex_reg_next.reg_write1),
        .id_valid1          (id_ex_reg_next.valid1),
        .id_mem_read0       (id_ex_reg_next.mem_read0),
        .id_mem_read1       (id_ex_reg_next.mem_read1),
        .id_mem_write0      (id_ex_reg_next.mem_write0),
        .id_mem_write1      (id_ex_reg_next.mem_write1),
        .id_rs1_addr0       (id_ex_reg_next.rs1_addr0),
        .id_rs2_addr0       (id_ex_reg_next.rs2_addr0),
        .id_rs1_addr1       (id_ex_reg_next.rs1_addr1),
        .id_rs2_addr1       (id_ex_reg_next.rs2_addr1),
        // EX/MEM stage info
        .exmem_rd_addr0     (ex_mem_reg.rd_addr0),
        .exmem_reg_write0   (ex_mem_reg.reg_write0),
        .exmem_mem_read0    (ex_mem_reg.mem_read0),
        .exmem_rd_addr1     (ex_mem_reg.rd_addr1),
        .exmem_reg_write1   (ex_mem_reg.reg_write1),
        // MEM/WB stage info
        .memwb_rd_addr0     (mem_wb_reg.rd_addr0),
        .memwb_reg_write0   (mem_wb_reg.reg_write0),
        .memwb_rd_addr1     (mem_wb_reg.rd_addr1),
        .memwb_reg_write1   (mem_wb_reg.reg_write1),
        // Branch resolution
        .branch_resolve     (branch_resolve),
        .branch_mispredict  (branch_mispredict),
        // Output control signals
        .stall              (stall),
        .flush_if_id        (flush_if_id),
        .flush_id_ex        (flush_id_ex),
        .stall_fetch        (stall_fetch)
    );

    // ========================================================================
    // Module Instantiation: Execute Unit
    // ========================================================================
    execute_unit u_execute_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        // ID/EX input
        .id_ex_in           (id_ex_reg),
        // Forwarding from MEM/WB
        .memwb_write_data0  (mem_wb_reg.write_data0),
        .memwb_rd_addr0     (mem_wb_reg.rd_addr0),
        .memwb_reg_write0   (mem_wb_reg.reg_write0),
        .memwb_write_data1  (mem_wb_reg.write_data1),
        .memwb_rd_addr1     (mem_wb_reg.rd_addr1),
        .memwb_reg_write1   (mem_wb_reg.reg_write1),
        // Forwarding from EX/MEM
        .exmem_alu_result0  (ex_mem_reg.alu_result0),
        .exmem_rd_addr0     (ex_mem_reg.rd_addr0),
        .exmem_reg_write0   (ex_mem_reg.reg_write0),
        .exmem_alu_result1  (ex_mem_reg.alu_result1),
        .exmem_rd_addr1     (ex_mem_reg.rd_addr1),
        .exmem_reg_write1   (ex_mem_reg.reg_write1),
        // EX/MEM output
        .ex_mem_out         (ex_mem_reg_next),
        // Branch resolution
        .branch_resolve     (branch_resolve),
        .branch_taken       (branch_taken),
        .branch_target      (branch_target),
        .branch_mispredict  (branch_mispredict),
        .branch_correct_pc  (branch_correct_pc),
        // Branch predictor update
        .bp_update_valid    (bp_update_valid),
        .bp_update_pc       (bp_update_pc),
        .bp_update_taken    (bp_update_taken),
        .bp_update_target   (bp_update_target),
        .bp_update_br_type  (bp_update_br_type)
    );

    // ========================================================================
    // Module Instantiation: Memory Unit
    // ========================================================================
    memory_unit u_memory_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        .ex_mem_in      (ex_mem_reg),
        .dmem_addr0     (dmem_addr0),
        .dmem_wdata0    (dmem_wdata0),
        .dmem_we0       (dmem_we0),
        .dmem_be0       (dmem_be0),
        .dmem_rdata0    (dmem_rdata0),
        .dmem_addr1     (dmem_addr1),
        .dmem_wdata1    (dmem_wdata1),
        .dmem_we1       (dmem_we1),
        .dmem_be1       (dmem_be1),
        .dmem_rdata1    (dmem_rdata1),
        .mem_wb_out     (mem_wb_reg_next)
    );

    // ========================================================================
    // Module Instantiation: Writeback Unit
    // ========================================================================
    writeback_unit u_writeback_unit (
        .clk        (clk),
        .rst_n      (rst_n),
        .mem_wb_in  (mem_wb_reg),
        .rf_waddr0  (rf_waddr0),
        .rf_wdata0  (rf_wdata0),
        .rf_we0     (rf_we0),
        .rf_waddr1  (rf_waddr1),
        .rf_wdata1  (rf_wdata1),
        .rf_we1     (rf_we1)
    );

    // ========================================================================
    // Pipeline Register Update Logic
    // ========================================================================

    // RAS flush: clear speculative RAS entries on branch mispredict
    assign ras_flush = flush_if_id;

    // ----- IF/ID Pipeline Register -----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            if_id_reg <= '0;
        end else if (flush_if_id) begin
            // Branch misprediction: clear all fetched instructions
            if_id_reg <= '0;
        end else if (!stall_fetch) begin
            // Normal operation: latch fetch unit output
            if_id_reg <= if_id_reg_next;
        end
        // On stall: hold current value
    end

    // ----- ID/EX Pipeline Register -----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_ex_reg <= '0;
        end else if (flush_id_ex) begin
            // Stall or branch flush: clear both lanes
            id_ex_reg <= '0;
        end else begin
            // Normal operation: latch decode unit output
            id_ex_reg <= id_ex_reg_next;
        end
    end

    // ----- EX/MEM Pipeline Register (always flows) -----
    always_ff @(posedge clk) begin
        if (!rst_n)
            ex_mem_reg <= '0;
        else
            ex_mem_reg <= ex_mem_reg_next;
    end

    // ----- MEM/WB Pipeline Register (always flows) -----
    always_ff @(posedge clk) begin
        if (!rst_n)
            mem_wb_reg <= '0;
        else
            mem_wb_reg <= mem_wb_reg_next;
    end

endmodule

// ============================================================================
// 模块 : riscv_core
// 项目 : RISC-V 双发射超标量处理器（优化版）
// 说明 : 顶层CPU核心模块，集成所有流水级。
//        - 优化：双端口数据存储器、RAS、128条目2路BTB
//        - 例化：取指、译码、执行、访存、写回单元
//        - 管理流水线寄存器：IF/ID、ID/EX、EX/MEM、MEM/WB
//        - 每个流水线寄存器携带双通道（2宽）数据
//        - 处理全局阻塞/刷新信号分发
//        - 哈佛架构：独立的指令和数据端口
// ============================================================================

`include "defines.sv"
`include "types.sv"

module riscv_core (
    input  logic        clk,            // 系统时钟
    input  logic        rst_n,          // 同步复位，低有效

    // ----- 指令存储器接口（哈佛架构，64位读）-----
    output logic [31:0] imem_addr,      // 指令存储器地址
    input  logic [63:0] imem_rdata,     // 64位指令数据（2条指令）

    // ----- 数据存储器端口0（Lane 0，32位读写）-----
    output logic [31:0] dmem_addr0,     // Lane 0数据存储器地址
    output logic [31:0] dmem_wdata0,    // Lane 0数据存储器写数据
    output logic        dmem_we0,       // Lane 0数据存储器写使能
    output logic [3:0]  dmem_be0,       // Lane 0数据存储器字节使能
    input  logic [31:0] dmem_rdata0,    // Lane 0数据存储器读数据

    // ----- 数据存储器端口1（Lane 1，32位读写）-----
    output logic [31:0] dmem_addr1,     // Lane 1数据存储器地址
    output logic [31:0] dmem_wdata1,    // Lane 1数据存储器写数据
    output logic        dmem_we1,       // Lane 1数据存储器写使能
    output logic [3:0]  dmem_be1,       // Lane 1数据存储器字节使能
    input  logic [31:0] dmem_rdata1     // Lane 1数据存储器读数据
);

    // ========================================================================
    // 流水线寄存器
    // ========================================================================
    if_id_reg_t  if_id_reg,  if_id_reg_next;
    id_ex_reg_t  id_ex_reg,  id_ex_reg_next;
    ex_mem_reg_t ex_mem_reg, ex_mem_reg_next;
    mem_wb_reg_t mem_wb_reg, mem_wb_reg_next;

    // ========================================================================
    // 全局控制信号
    // ========================================================================
    logic stall;              // 流水线阻塞（检测到冒险）
    logic flush_if_id;        // 刷新IF/ID寄存器（分支预测错误）
    logic flush_id_ex;        // 刷新ID/EX寄存器（阻塞或预测错误）
    logic stall_fetch;        // 阻塞指令取指

    // 分支解析信号（来自执行阶段）
    logic        branch_resolve;
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        branch_mispredict;
    logic [31:0] branch_correct_pc;

    // 分支预测器接口信号
    logic [31:0] bp_pc;
    logic        bp_hit;
    logic        bp_taken;
    logic [31:0] bp_target;

    // 分支预测器预解码信号（来自取指单元）
    logic        pre_is_jal;
    logic        pre_is_jalr;
    logic [31:0] pre_jal_target;

    // 分支预测器更新信号
    logic        bp_update_valid;
    logic [31:0] bp_update_pc;
    logic        bp_update_taken;
    logic [31:0] bp_update_target;
    logic [1:0]  bp_update_br_type;

    // RAS刷新信号（分支预测错误时）
    logic        ras_flush;

    // 寄存器文件读地址（来自译码单元）
    logic [4:0]  rf_rs1_addr0, rf_rs2_addr0;
    logic [4:0]  rf_rs1_addr1, rf_rs2_addr1;

    // 寄存器文件读数据
    logic [31:0] rf_rs1_data0, rf_rs2_data0;
    logic [31:0] rf_rs1_data1, rf_rs2_data1;

    // 寄存器文件写信号（来自写回单元）
    logic [4:0]  rf_waddr0, rf_waddr1;
    logic [31:0] rf_wdata0, rf_wdata1;
    logic        rf_we0, rf_we1;

    // ========================================================================
    // 模块例化：分支预测器
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
    // 模块例化：取指单元
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
    // 模块例化：寄存器文件（4读端口，2写端口）
    // ========================================================================
    regfile u_regfile (
        .clk    (clk),
        .rst_n  (rst_n),
        // 读端口
        .raddr0 (rf_rs1_addr0),     // Lane 0 rs1
        .rdata0 (rf_rs1_data0),
        .raddr1 (rf_rs2_addr0),     // Lane 0 rs2
        .rdata1 (rf_rs2_data0),
        .raddr2 (rf_rs1_addr1),     // Lane 1 rs1
        .rdata2 (rf_rs1_data1),
        .raddr3 (rf_rs2_addr1),     // Lane 1 rs2
        .rdata3 (rf_rs2_data1),
        // 写端口
        .waddr0 (rf_waddr0),        // Lane 0 写回
        .wdata0 (rf_wdata0),
        .we0    (rf_we0),
        .waddr1 (rf_waddr1),        // Lane 1 写回
        .wdata1 (rf_wdata1),
        .we1    (rf_we1)
    );

    // ========================================================================
    // 模块例化：译码单元
    // ========================================================================
    decode_unit u_decode_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        // IF/ID 输入
        .id_pc0         (if_id_reg.pc0),
        .id_inst0       (if_id_reg.inst0),
        .id_valid0      (if_id_reg.valid0),
        .id_pc1         (if_id_reg.pc1),
        .id_inst1       (if_id_reg.inst1),
        .id_valid1      (if_id_reg.valid1),
        .id_bp_taken0   (if_id_reg.bp_taken0),
        .id_bp_target0  (if_id_reg.bp_target0),
        // 寄存器文件读数据
        .rf_rs1_data0   (rf_rs1_data0),
        .rf_rs2_data0   (rf_rs2_data0),
        .rf_rs1_data1   (rf_rs1_data1),
        .rf_rs2_data1   (rf_rs2_data1),
        // 寄存器文件读地址
        .rf_rs1_addr0   (rf_rs1_addr0),
        .rf_rs2_addr0   (rf_rs2_addr0),
        .rf_rs1_addr1   (rf_rs1_addr1),
        .rf_rs2_addr1   (rf_rs2_addr1),
        // ID/EX 输出
        .id_ex_out      (id_ex_reg_next)
    );

    // ========================================================================
    // 模块例化：冒险单元
    // ========================================================================
    hazard_unit u_hazard_unit (
        // ID 阶段信息
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
        // EX/MEM 阶段信息
        .exmem_rd_addr0     (ex_mem_reg.rd_addr0),
        .exmem_reg_write0   (ex_mem_reg.reg_write0),
        .exmem_mem_read0    (ex_mem_reg.mem_read0),
        .exmem_rd_addr1     (ex_mem_reg.rd_addr1),
        .exmem_reg_write1   (ex_mem_reg.reg_write1),
        // MEM/WB 阶段信息
        .memwb_rd_addr0     (mem_wb_reg.rd_addr0),
        .memwb_reg_write0   (mem_wb_reg.reg_write0),
        .memwb_rd_addr1     (mem_wb_reg.rd_addr1),
        .memwb_reg_write1   (mem_wb_reg.reg_write1),
        // 分支解析
        .branch_resolve     (branch_resolve),
        .branch_mispredict  (branch_mispredict),
        // 输出控制信号
        .stall              (stall),
        .flush_if_id        (flush_if_id),
        .flush_id_ex        (flush_id_ex),
        .stall_fetch        (stall_fetch)
    );

    // ========================================================================
    // 模块例化：执行单元
    // ========================================================================
    execute_unit u_execute_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        // ID/EX 输入
        .id_ex_in           (id_ex_reg),
        // 来自 MEM/WB 的前推
        .memwb_write_data0  (mem_wb_reg.write_data0),
        .memwb_rd_addr0     (mem_wb_reg.rd_addr0),
        .memwb_reg_write0   (mem_wb_reg.reg_write0),
        .memwb_write_data1  (mem_wb_reg.write_data1),
        .memwb_rd_addr1     (mem_wb_reg.rd_addr1),
        .memwb_reg_write1   (mem_wb_reg.reg_write1),
        // 来自 EX/MEM 的前推
        .exmem_alu_result0  (ex_mem_reg.alu_result0),
        .exmem_rd_addr0     (ex_mem_reg.rd_addr0),
        .exmem_reg_write0   (ex_mem_reg.reg_write0),
        .exmem_alu_result1  (ex_mem_reg.alu_result1),
        .exmem_rd_addr1     (ex_mem_reg.rd_addr1),
        .exmem_reg_write1   (ex_mem_reg.reg_write1),
        // EX/MEM 输出
        .ex_mem_out         (ex_mem_reg_next),
        // 分支解析
        .branch_resolve     (branch_resolve),
        .branch_taken       (branch_taken),
        .branch_target      (branch_target),
        .branch_mispredict  (branch_mispredict),
        .branch_correct_pc  (branch_correct_pc),
        // 分支预测器更新
        .bp_update_valid    (bp_update_valid),
        .bp_update_pc       (bp_update_pc),
        .bp_update_taken    (bp_update_taken),
        .bp_update_target   (bp_update_target),
        .bp_update_br_type  (bp_update_br_type)
    );

    // ========================================================================
    // 模块例化：访存单元
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
    // 模块例化：写回单元
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
    // 流水线寄存器更新逻辑
    // ========================================================================

    // RAS刷新：分支预测错误时清除推测性RAS条目
    assign ras_flush = flush_if_id;

    // ----- IF/ID 流水线寄存器 -----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            if_id_reg <= '0;
        end else if (flush_if_id) begin
            // 分支预测错误：清除所有已取指指令
            if_id_reg <= '0;
        end else if (!stall_fetch) begin
            // 正常运行：锁存取指单元输出
            if_id_reg <= if_id_reg_next;
        end
        // 阻塞时：保持当前值
    end

    // ----- ID/EX 流水线寄存器 -----
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            id_ex_reg <= '0;
        end else if (flush_id_ex) begin
            // 阻塞或分支刷新：清除两个通道
            id_ex_reg <= '0;
        end else begin
            // 正常运行：锁存译码单元输出
            id_ex_reg <= id_ex_reg_next;
        end
    end

    // ----- EX/MEM 流水线寄存器（始终流通）-----
    always_ff @(posedge clk) begin
        if (!rst_n)
            ex_mem_reg <= '0;
        else
            ex_mem_reg <= ex_mem_reg_next;
    end

    // ----- MEM/WB 流水线寄存器（始终流通）-----
    always_ff @(posedge clk) begin
        if (!rst_n)
            mem_wb_reg <= '0;
        else
            mem_wb_reg <= mem_wb_reg_next;
    end

endmodule

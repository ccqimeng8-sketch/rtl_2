// ============================================================================
// 模块 : hazard_unit
// 项目: RISC-V 2发射超标量处理器（优化版）
// 描述: 冒险检测与流水线控制单元。
//       检测以下冒险：
//       1. 结构冒险：通道间寄存器写冲突
//       2. 结构冒险：两个通道同时访问相同地址的内存
//       3. 控制冒险：分支预测错误导致流水线刷新
//
//       注：本设计中加载-使用冒险不需要停顿。
//       当Load指令处于MEM/WB阶段时，依赖指令处于EX阶段。
//       MEM/WB → EX的前推网络组合逻辑提供正确的Load数据，
//       结果在下一个时钟边沿被捕获到EX/MEM中。无需停顿。
//
//       注：使用双端口数据存储器，两个通道可同时访问内存。
//       相同地址的冲突在此检测。
//
//       生成停顿(stall)、刷新(flush)和取指停顿(fetch_stall)信号。
// ============================================================================

`include "defines.sv"
`include "types.sv"

module hazard_unit (
    // ----- ID阶段指令信息 -----
    input  logic [4:0]  id_rd_addr0,        // 通道0目标寄存器
    input  logic        id_reg_write0,      // 通道0将要写寄存器
    input  logic        id_valid0,          // 通道0有效
    input  logic [4:0]  id_rd_addr1,        // 通道1目标寄存器
    input  logic        id_reg_write1,      // 通道1将要写寄存器
    input  logic        id_valid1,          // 通道1有效
    input  logic        id_mem_read0,       // 通道0是Load指令
    input  logic        id_mem_read1,       // 通道1是Load指令
    input  logic        id_mem_write0,      // 通道0是Store指令
    input  logic        id_mem_write1,      // 通道1是Store指令
    input  logic [4:0]  id_rs1_addr0,       // 通道0源寄存器1
    input  logic [4:0]  id_rs2_addr0,       // 通道0源寄存器2
    input  logic [4:0]  id_rs1_addr1,       // 通道1源寄存器1
    input  logic [4:0]  id_rs2_addr1,       // 通道1源寄存器2

    // ----- EX/MEM阶段信息 -----
    input  logic [4:0]  exmem_rd_addr0,     // EX/MEM 通道0目标寄存器
    input  logic        exmem_reg_write0,   // EX/MEM 通道0写寄存器
    input  logic        exmem_mem_read0,    // EX/MEM 通道0是Load
    input  logic [4:0]  exmem_rd_addr1,     // EX/MEM 通道1目标寄存器
    input  logic        exmem_reg_write1,   // EX/MEM 通道1写寄存器

    // ----- MEM/WB阶段信息 -----
    input  logic [4:0]  memwb_rd_addr0,     // MEM/WB 通道0目标寄存器
    input  logic        memwb_reg_write0,   // MEM/WB 通道0写寄存器
    input  logic [4:0]  memwb_rd_addr1,     // MEM/WB 通道1目标寄存器
    input  logic        memwb_reg_write1,   // MEM/WB 通道1写寄存器

    // ----- 分支解析信号 -----
    input  logic        branch_resolve,     // 分支指令在EX阶段解析
    input  logic        branch_mispredict,  // 分支预测错误

    // ----- 输出控制信号 -----
    output logic        stall,              // 流水线停顿（所有阶段保持）
    output logic        flush_if_id,        // 刷新IF/ID流水线寄存器
    output logic        flush_id_ex,        // 刷新ID/EX流水线寄存器
    output logic        stall_fetch          // 停顿取指
);

    // ========================================================================
    // 1. 结构冒险检测
    // ========================================================================
    // 寄存器写冲突：两个通道同时写入相同寄存器时无法继续执行。
    // 译码单元也通过eff_valid1机制处理此情况，但此处作为安全检查保留。

    logic wr_struct_hazard;
    assign wr_struct_hazard = id_valid0 & id_valid1 &
        id_reg_write0 & id_reg_write1 &
        (id_rd_addr0 != 5'b0) & (id_rd_addr1 != 5'b0) &
        (id_rd_addr0 == id_rd_addr1);

    // ========================================================================
    // 2. 内存地址冲突检测（双端口）
    // ========================================================================
    // 当两个通道同时访问数据存储器时，检查冲突：
    //   - 相同地址 + 至少一个写操作 → 结构冒险
    // 通道0具有优先级；通道1被停顿。

    logic mem_conflict;

    // 基于ID阶段信息计算通道0和通道1的内存地址
    // 在ID阶段，地址为rs1 + imm（ALU前）。我们通过检查
    // 两个通道是否都有活跃的内存操作来近似判断。
    // 完整的地址比较在EX/MEM阶段进行。
    // 目前：检测两个通道是否都发出潜在同区域的内存操作。
    // 这是保守的做法：任一通道有任何内存操作就停顿。

    // 保守策略：若两个通道都有内存操作（Load或Store），停顿通道1。
    // 后续可通过实际地址比较进一步优化。
    logic dual_mem_op;
    assign dual_mem_op = (id_mem_read0 | id_mem_write0) &
                         (id_mem_read1 | id_mem_write1) &
                         id_valid0 & id_valid1;

    assign mem_conflict = dual_mem_op;

    // ========================================================================
    // 3. 控制冒险（分支预测错误）
    // ========================================================================
    // 当分支在EX阶段解析且预测错误时，
    // 刷新IF/ID和ID/EX流水线寄存器。

    logic control_flush;
    assign control_flush = branch_resolve & branch_mispredict;

    // ========================================================================
    // 综合输出信号
    // ========================================================================

    // 停顿：检测到结构冒险或内存冲突时置位
    assign stall = wr_struct_hazard | mem_conflict;

    // 停顿取指：与流水线停顿相同
    assign stall_fetch = stall;

    // 刷新IF/ID：分支预测错误时（丢弃取指错误的指令）
    assign flush_if_id = control_flush;

    // 刷新ID/EX：停顿（插入气泡）或分支预测错误时
    assign flush_id_ex = stall | control_flush;

endmodule

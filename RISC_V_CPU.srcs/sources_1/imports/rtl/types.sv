// ============================================================================
// 模块 : types.sv
// 项目: RISC-V 双发射超标量处理器
// 描述: 公共类型定义 - 流水线寄存器结构体、枚举
// ============================================================================

`ifndef TYPES_SV
`define TYPES_SV

// ----------------------------------------------------------------------------
// IF/ID 流水线寄存器
// 传递 2 条取指指令 + 分支预测信息
// ----------------------------------------------------------------------------
typedef struct packed {
    // 通道 0
    logic [31:0] pc0;           // 通道 0 的 PC 值
    logic [31:0] inst0;         // 通道 0 的指令字
    logic        valid0;        // 通道 0 有效标志

    // 通道 1
    logic [31:0] pc1;           // 通道 1 的 PC 值
    logic [31:0] inst1;         // 通道 1 的指令字
    logic        valid1;        // 通道 1 有效标志

    // 分支预测信息 (仅通道 0, 因为分支必须在通道 0)
    logic        bp_taken0;     // 分支预测为跳转
    logic [31:0] bp_target0;    // 预测的分支目标地址
} if_id_reg_t;

// ----------------------------------------------------------------------------
// ID/EX 流水线寄存器
// 传递译码后的控制信号 + 寄存器数据, 覆盖 2 个通道
// ----------------------------------------------------------------------------
typedef struct packed {
    // ===== 通道 0 =====
    logic [31:0] pc0;           // 通道 0 指令的 PC
    logic [4:0]  rd_addr0;      // 目的寄存器地址
    logic [31:0] rs1_data0;     // 源寄存器 1 数据 (来自寄存器堆)
    logic [31:0] rs2_data0;     // 源寄存器 2 数据 (来自寄存器堆)
    logic [31:0] imm0;          // 译码后的立即数值
    logic [2:0]  alu_op0;       // ALU 操作码
    logic        alu_src0;      // ALU 源选择: 0=rs2, 1=imm
    logic        reg_write0;    // 寄存器写使能
    logic        mem_read0;     // 存储器读使能 (Load)
    logic        mem_write0;    // 存储器写使能 (Store)
    logic [2:0]  mem_width0;    // 访存宽度 (B/H/W)
    logic        mem_sign0;     // 存储器符号扩展标志
    logic        branch0;       // 分支指令标志
    logic        jump0;         // 跳转指令标志
    logic        auipc0;        // AUIPC 指令标志
    logic        lui0;          // LUI 指令标志
    logic [2:0]  funct3_0;      // funct3, 用于分支条件判断
    logic [4:0]  rs1_addr0;     // 源寄存器 1 地址 (用于前推比较)
    logic [4:0]  rs2_addr0;     // 源寄存器 2 地址 (用于前推比较)
    logic        valid0;        // 通道 0 有效标志

    // ===== 通道 1 =====
    logic [31:0] pc1;
    logic [4:0]  rd_addr1;
    logic [31:0] rs1_data1;
    logic [31:0] rs2_data1;
    logic [31:0] imm1;
    logic [2:0]  alu_op1;
    logic        alu_src1;
    logic        reg_write1;
    logic        mem_read1;
    logic        mem_write1;
    logic [2:0]  mem_width1;
    logic        mem_sign1;
    logic        branch1;
    logic        jump1;
    logic        auipc1;        // AUIPC 指令标志
    logic        lui1;          // LUI 指令标志
    logic [2:0]  funct3_1;
    logic [4:0]  rs1_addr1;
    logic [4:0]  rs2_addr1;
    logic        valid1;

    // 分支预测信息 (用于 BTB/BHT 更新)
    logic        bp_taken0;     // 分支是否被预测为跳转?
    logic [31:0] bp_target0;    // 预测的目标地址
} id_ex_reg_t;

// ----------------------------------------------------------------------------
// EX/MEM 流水线寄存器
// 传递 ALU 结果 + 访存控制, 覆盖 2 个通道
// ----------------------------------------------------------------------------
typedef struct packed {
    // ===== 通道 0 =====
    logic [31:0] alu_result0;   // ALU 计算结果
    logic [31:0] rs2_data0;     // 存储数据 (rs2 值, 已前推)
    logic [4:0]  rd_addr0;      // 目的寄存器地址
    logic        reg_write0;    // 寄存器写使能
    logic        mem_read0;     // 存储器读使能
    logic        mem_write0;    // 存储器写使能
    logic [2:0]  mem_width0;    // 访存宽度
    logic        mem_sign0;     // 符号扩展标志
    logic        branch_taken0; // 实际分支跳转结果
    logic [31:0] branch_target0;// 计算得到的分支目标
    logic        valid0;

    // ===== 通道 1 =====
    logic [31:0] alu_result1;
    logic [31:0] rs2_data1;
    logic [4:0]  rd_addr1;
    logic        reg_write1;
    logic        mem_read1;
    logic        mem_write1;
    logic [2:0]  mem_width1;
    logic        mem_sign1;
    logic        branch_taken1;
    logic [31:0] branch_target1;
    logic        valid1;
} ex_mem_reg_t;

// ----------------------------------------------------------------------------
// MEM/WB 流水线寄存器
// 传递最终的写回数据, 覆盖 2 个通道
// ----------------------------------------------------------------------------
typedef struct packed {
    // ===== 通道 0 =====
    logic [31:0] write_data0;   // 最终写入数据 (ALU 结果或 Load 数据)
    logic [4:0]  rd_addr0;      // 目的寄存器地址
    logic        reg_write0;    // 寄存器写使能
    logic        valid0;        // 通道 0 有效标志

    // ===== 通道 1 =====
    logic [31:0] write_data1;
    logic [4:0]  rd_addr1;
    logic        reg_write1;
    logic        valid1;
} mem_wb_reg_t;

`endif // TYPES_SV

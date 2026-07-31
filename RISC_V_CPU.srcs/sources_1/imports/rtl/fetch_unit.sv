// ============================================================================
// 模块 : fetch_unit
// 项目: RISC-V 双发射超标量处理器
// 描述: 双宽度超标量流水线的取指单元。
//              - 管理PC寄存器，更新优先级如下：
//                1) 分支误预测修正（最高优先级）
//                2) BTB 预测跳转
//                3) 顺序取指（PC + 4）
//                4) 停顿（保持PC不变）
//              - 从指令存储器读取64位（2条指令）
//              - 处理8字节对齐的指令提取
//              - 当PC[2]==1（非对齐）时，仅发射1条有效指令
// ============================================================================

`include "defines.sv"

module fetch_unit (
    input  logic        clk,                    // 时钟
    input  logic        rst_n,                  // 同步复位，低有效

    // ----- 指令存储器接口 -----
    output logic [31:0] imem_addr,              // 指令存储器地址（8字节对齐）
    input  logic [63:0] imem_rdata,             // 64位指令数据

    // ----- 分支预测器接口 -----
    output logic [31:0] bp_pc,                  // 发送到预测器的当前PC
    input  logic        bp_hit,                 // BTB命中信号
    input  logic        bp_taken,               // 预测分支跳转
    input  logic [31:0] bp_target,              // 预测目标地址

    // ----- 流水线控制信号 -----
    input  logic        stall,                  // 保持PC（不前进）
    input  logic        flush,                  // 刷新IF/ID寄存器

    // ----- 分支决议（来自执行阶段） -----
    input  logic        branch_resolve,         // 分支已决议
    input  logic        branch_mispredict,      // 预测错误
    input  logic [31:0] branch_correct_pc,      // 决议后的正确PC

    // ----- 输出至IF/ID流水线寄存器 -----
    output logic [31:0] fetch_pc0,              // 通道0 PC
    output logic [31:0] fetch_pc1,              // 通道1 PC
    output logic [31:0] fetch_inst0,            // 通道0指令
    output logic [31:0] fetch_inst1,            // 通道1指令
    output logic        fetch_valid0,           // 通道0有效
    output logic        fetch_valid1,           // 通道1有效
    output logic        fetch_bp_taken0,        // 通道0分支预测跳转
    output logic [31:0] fetch_bp_target0,       // 通道0预测目标

    // ----- 预译码输出（用于分支预测器RAS） -----
    output logic        pre_is_jal,             // 通道0指令为JAL
    output logic        pre_is_jalr,            // 通道0指令为JALR
    output logic [31:0] pre_jal_target          // JAL目标地址 = PC + 立即数
);

    // ------------------------------------------------------------------------
    // PC寄存器
    // ------------------------------------------------------------------------
    logic [31:0] pc_reg;

    // ------------------------------------------------------------------------
    // 下一PC逻辑（组合逻辑）
    // 优先级：误预测 > BTB预测跳转 > 顺序取指
    // 顺序取指每次前进8（每周期取2条指令）
    // ------------------------------------------------------------------------
    logic [31:0] pc_next;
    logic [31:0] seq_pc; // 顺序下一PC

    // 始终取2条指令（8字节），因此PC总是前进8
    assign seq_pc = pc_reg + 32'd8;

    always_comb begin
        if (branch_resolve && branch_mispredict) begin
            // 最高优先级：修正分支误预测
            pc_next = branch_correct_pc;
        end else if (bp_hit && bp_taken) begin
            // 第二优先级：BTB预测跳转 -> 跳转至目标地址
            pc_next = bp_target;
        end else begin
            // 默认：顺序取指
            pc_next = seq_pc;
        end
    end

    // ------------------------------------------------------------------------
    // PC寄存器更新（同步时序）
    // - 复位时：PC跳转至复位向量
    // - 停顿时：保持当前PC
    // - 其他情况：更新为pc_next
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_reg <= `PC_RESET_VALUE;
        end else if (branch_resolve && branch_mispredict) begin
            // 分支修正始终生效
            pc_reg <= branch_correct_pc;
        end else if (!stall) begin
            if (bp_hit && bp_taken)
                pc_reg <= bp_target;
            else
                pc_reg <= seq_pc;
        end
        // 当停顿信号有效时，pc_reg保持原值
    end

    // ------------------------------------------------------------------------
    // 指令存储器地址（8字节对齐）
    // ------------------------------------------------------------------------
    assign imem_addr = {pc_reg[31:3], 3'b000};

    // ------------------------------------------------------------------------
    // 分支预测器PC输入
    // ------------------------------------------------------------------------
    assign bp_pc = pc_reg;

    // ------------------------------------------------------------------------
    // 指令提取（始终8字节对齐，每周期取2条指令）
    // inst0 = rdata[31:0]   （低32位）
    // inst1 = rdata[63:32]  （高32位）
    // ------------------------------------------------------------------------

    // 通道0指令及有效性
    assign fetch_inst0  = imem_rdata[31:0];
    assign fetch_valid0 = 1'b1;  // 取指时通道0始终有效

    // 通道1指令及有效性
    assign fetch_inst1  = imem_rdata[63:32];
    assign fetch_valid1 = 1'b1;  // 通道1始终有效（始终取2条指令）

    // ------------------------------------------------------------------------
    // PC分配至各通道
    // ------------------------------------------------------------------------
    assign fetch_pc0 = pc_reg;
    assign fetch_pc1 = pc_reg + 32'd4;

    // ------------------------------------------------------------------------
    // 分支预测信息输出
    // - 仅通道0可以是分支指令（分支指令必须位于通道0）
    // - 传递预测结果，供后续执行阶段验证
    // ------------------------------------------------------------------------
    assign fetch_bp_taken0  = bp_taken;
    assign fetch_bp_target0 = bp_target;

    // ------------------------------------------------------------------------
    // 预译码（用于分支预测器RAS支持）
    // 检测通道0指令中的JAL/JALR，用于RAS预测
    // ------------------------------------------------------------------------
    wire [6:0] inst0_opcode = imem_rdata[6:0];

    assign pre_is_jal  = (inst0_opcode == `OPCODE_JAL);
    assign pre_is_jalr = (inst0_opcode == `OPCODE_JALR);

    // JAL目标地址 = PC + J型立即数
    // J型：{inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
    assign pre_jal_target = pc_reg + {
        {11{imem_rdata[31]}},
        imem_rdata[31],
        imem_rdata[19:12],
        imem_rdata[20],
        imem_rdata[30:21],
        1'b0
    };

endmodule

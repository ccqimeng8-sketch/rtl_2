// ============================================================================
// 模块名 : execute_unit
// 项目  : RISC-V 双发射超标量处理器
// 描述  : 双通道执行单元，包含 2 个 ALU 和前推网络。
//        - Lane 0 ALU 处理 Lane 0 指令
//        - Lane 1 ALU 处理 Lane 1 指令
//        - 前推路径：EX/MEM -> EX、MEM/WB -> EX（双通道均支持）
//        - 分支条件判断在 Lane 0 完成
//        - 分支预测失败检测与修正
//        - BTB/BHT 更新信号生成
// ============================================================================

`include "defines.sv"
`include "types.sv"

module execute_unit (
    input  logic        clk,            // 时钟
    input  logic        rst_n,          // 同步复位，低有效

    // ----- 来自 ID/EX 流水线寄存器的输入 -----
    input  id_ex_reg_t  id_ex_in,       // 译码后的指令对

    // ----- 来自 MEM/WB 级的前推数据 -----
    input  logic [31:0] memwb_write_data0,  // MEM/WB Lane 0 写回数据
    input  logic [4:0]  memwb_rd_addr0,     // MEM/WB Lane 0 目标寄存器
    input  logic        memwb_reg_write0,   // MEM/WB Lane 0 寄存器写使能
    input  logic [31:0] memwb_write_data1,  // MEM/WB Lane 1 写回数据
    input  logic [4:0]  memwb_rd_addr1,     // MEM/WB Lane 1 目标寄存器
    input  logic        memwb_reg_write1,   // MEM/WB Lane 1 寄存器写使能

    // ----- 来自 EX/MEM 级的前推数据 -----
    input  logic [31:0] exmem_alu_result0,  // EX/MEM Lane 0 ALU 结果
    input  logic [4:0]  exmem_rd_addr0,     // EX/MEM Lane 0 目标寄存器
    input  logic        exmem_reg_write0,   // EX/MEM Lane 0 寄存器写使能
    input  logic [31:0] exmem_alu_result1,  // EX/MEM Lane 1 ALU 结果
    input  logic [4:0]  exmem_rd_addr1,     // EX/MEM Lane 1 目标寄存器
    input  logic        exmem_reg_write1,   // EX/MEM Lane 1 寄存器写使能

    // ----- 输出至 EX/MEM 流水线寄存器 -----
    output ex_mem_reg_t ex_mem_out,

    // ----- 分支解析信号 -----
    output logic        branch_resolve,     // 本周期解析了一条分支
    output logic        branch_taken,       // 实际分支跳转结果
    output logic [31:0] branch_target,      // 计算得到的分支目标地址
    output logic        branch_mispredict,  // 预测错误
    output logic [31:0] branch_correct_pc,  // 预测错误时的正确 PC

    // ----- 分支预测器更新接口 -----
    output logic        bp_update_valid,    // 更新 BTB/BHT
    output logic [31:0] bp_update_pc,       // 待更新的分支 PC
    output logic        bp_update_taken,    // 实际跳转结果
    output logic [31:0] bp_update_target,   // 实际目标地址
    output logic [1:0]  bp_update_br_type   // 00=条件分支, 01=JAL, 10=JALR
);

    // ========================================================================
    // 前推网络
    // ========================================================================
    // 为每个 ALU 操作数从以下来源选择最新的结果：
    //   优先级（从低到高）：寄存器堆 -> MEM/WB -> EX/MEM

    // ----- Lane 0 操作数 A 前推 -----
    logic [31:0] fwd_a0;
    always_comb begin
        fwd_a0 = id_ex_in.rs1_data0; // 默认：寄存器堆数值

        // MEM/WB 前推（较低优先级）
        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs1_addr0))
            fwd_a0 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs1_addr0))
            fwd_a0 = memwb_write_data1;

        // EX/MEM 前推（较高优先级）
        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs1_addr0))
            fwd_a0 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs1_addr0))
            fwd_a0 = exmem_alu_result1;
    end

    // ----- Lane 0 操作数 B 前推 -----
    logic [31:0] fwd_b0;
    always_comb begin
        fwd_b0 = id_ex_in.rs2_data0;

        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs2_addr0))
            fwd_b0 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs2_addr0))
            fwd_b0 = memwb_write_data1;

        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs2_addr0))
            fwd_b0 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs2_addr0))
            fwd_b0 = exmem_alu_result1;
    end

    // ----- Lane 1 操作数 A 前推 -----
    logic [31:0] fwd_a1;
    always_comb begin
        fwd_a1 = id_ex_in.rs1_data1;

        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs1_addr1))
            fwd_a1 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs1_addr1))
            fwd_a1 = memwb_write_data1;

        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs1_addr1))
            fwd_a1 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs1_addr1))
            fwd_a1 = exmem_alu_result1;
    end

    // ----- Lane 1 操作数 B 前推 -----
    logic [31:0] fwd_b1;
    always_comb begin
        fwd_b1 = id_ex_in.rs2_data1;

        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs2_addr1))
            fwd_b1 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs2_addr1))
            fwd_b1 = memwb_write_data1;

        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs2_addr1))
            fwd_b1 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs2_addr1))
            fwd_b1 = exmem_alu_result1;
    end

    // ========================================================================
    // ALU 输入选择
    // ========================================================================
    // op_a：始终来自前推后的 rs1（AUIPC/JAL 时使用 PC）
    // op_b：前推后的 rs2 或立即数（由 alu_src 选择）

    logic [31:0] alu_a0, alu_b0;
    logic [31:0] alu_a1, alu_b1;

    // Lane 0 ALU 输入
    always_comb begin
        // AUIPC 和 JAL：op_a = PC
        // JALR：op_a = rs1（fwd_a0），不使用 PC
        if (id_ex_in.auipc0 ||
            (id_ex_in.jump0 && (id_ex_in.alu_op0 == `ALU_OP_ADD) && !id_ex_in.alu_src0))
            alu_a0 = id_ex_in.pc0; // AUIPC/JAL：使用 PC
        else
            alu_a0 = fwd_a0;       // 普通：rs1 数据（JALR 也走这里）

        // LUI：op_a = 0（结果 = 0 + imm = imm）
        if (id_ex_in.lui0)
            alu_a0 = 32'b0;

        // op_b 选择：立即数或前推后的 rs2
        alu_b0 = id_ex_in.alu_src0 ? id_ex_in.imm0 : fwd_b0;
    end

    // Lane 1 ALU 输入
    always_comb begin
        alu_a1 = fwd_a1;

        if (id_ex_in.lui1)
            alu_a1 = 32'b0;        // LUI

        alu_b1 = id_ex_in.alu_src1 ? id_ex_in.imm1 : fwd_b1;
    end

    // ========================================================================
    // ALU 实例
    // ========================================================================

    logic [31:0] alu_result0, alu_result1;
    logic        alu_zero0, alu_zero1;
    logic        alu_less0, alu_less1;
    logic        alu_less_u0, alu_less_u1;

    alu u_alu0 (
        .op_a   (alu_a0),
        .op_b   (alu_b0),
        .alu_op (id_ex_in.alu_op0),
        .result (alu_result0),
        .zero   (alu_zero0),
        .less   (alu_less0),
        .less_u (alu_less_u0)
    );

    alu u_alu1 (
        .op_a   (alu_a1),
        .op_b   (alu_b1),
        .alu_op (id_ex_in.alu_op1),
        .result (alu_result1),
        .zero   (alu_zero1),
        .less   (alu_less1),
        .less_u (alu_less_u1)
    );

    // ========================================================================
    // 分支条件判断（仅 Lane 0）
    // ========================================================================
    // 分支指令使用相应的条件比较 rs1 和 rs2。
    // 比较使用前推后的操作数值。

    logic        branch_taken_internal;
    logic [31:0] branch_target_calc;

    // 分支目标 = PC + 立即数（B 型指令）
    assign branch_target_calc = id_ex_in.pc0 + id_ex_in.imm0;

    // 根据 funct3 判断分支条件
    always_comb begin
        branch_taken_internal = 1'b0;

        if (id_ex_in.branch0 && id_ex_in.valid0) begin
            case (id_ex_in.funct3_0)
                `FUNCT3_BEQ:  branch_taken_internal = alu_zero0;         // rs1 == rs2
                `FUNCT3_BNE:  branch_taken_internal = ~alu_zero0;        // rs1 != rs2
                `FUNCT3_BLT:  branch_taken_internal = alu_less0;         // rs1 < rs2（有符号）
                `FUNCT3_BGE:  branch_taken_internal = ~alu_less0;        // rs1 >= rs2（有符号）
                `FUNCT3_BLTU: branch_taken_internal = alu_less_u0;       // rs1 < rs2（无符号）
                `FUNCT3_BGEU: branch_taken_internal = ~alu_less_u0;      // rs1 >= rs2（无符号）
                default:      branch_taken_internal = 1'b0;
            endcase
        end
    end

    // ========================================================================
    // 分支预测失败检测
    // ========================================================================
    // 将实际分支结果与 BTB/BHT 的预测结果进行比较。
    // 满足以下条件之一时发生预测失败：
    //   1. 预测跳转但实际不跳转（或反之）
    //   2. 预测的目标地址与实际目标地址不同

    assign branch_resolve = id_ex_in.branch0 & id_ex_in.valid0;

    assign branch_taken = branch_taken_internal;
    assign branch_target = branch_target_calc;

    assign branch_mispredict = branch_resolve &
        ((branch_taken_internal != id_ex_in.bp_taken0) |
         (branch_taken_internal & (branch_target_calc != id_ex_in.bp_target0)));

    // 正确 PC：分支目标（若跳转）或顺序下一条 PC（若不跳转）
    // 由于每个周期总是取指 2 条指令，下一条顺序指令始终位于 PC+4
    //（同一取指对的 Lane 1）
    assign branch_correct_pc = branch_taken_internal ? branch_target_calc :
        (id_ex_in.pc0 + 32'd4);

    // ========================================================================
    // 分支预测器更新信号
    // ========================================================================
    // 每当一条分支指令被解析，就更新 BTB/BHT

    assign bp_update_valid  = (id_ex_in.branch0 | id_ex_in.jump0) & id_ex_in.valid0;
    assign bp_update_pc     = id_ex_in.pc0;
    assign bp_update_taken  = branch_taken_internal;
    assign bp_update_target = branch_target_calc;

    // 确定分支类型：00=条件分支, 01=JAL（调用）, 10=JALR（返回）
    assign bp_update_br_type = id_ex_in.branch0 ? 2'b00 :
                               (id_ex_in.jump0 ? (id_ex_in.alu_src0 ? 2'b10 : 2'b01) : 2'b00);

    // ========================================================================
    // JALR 目标地址修正
    // ========================================================================
    // JALR：PC <= (rs1 + imm) & ~1
    // ALU 计算 rs1 + imm；我们需要清除第 0 位。
    // 通过对跳转指令修改其结果来实现。

    logic [31:0] final_result0, final_result1;

    // 对于 JAL/JALR，确保目标的第 0 位被清除
    assign final_result0 = id_ex_in.jump0 ?
        {alu_result0[31:1], 1'b0} : alu_result0;

    // Lane 1 没有 JALR（若 Lane 0 跳转则被迫气泡）
    assign final_result1 = alu_result1;

    // ========================================================================
    // SLT/SLTU 结果修正
    // ========================================================================
    // SLT/SLTI：结果 = less ? 1 : 0
    // SLTU/SLTIU：结果 = less_u ? 1 : 0
    // ALU 执行 SUB；我们对这些操作覆盖其结果。

    logic [31:0] corrected_result0, corrected_result1;

    always_comb begin
        corrected_result0 = final_result0;

        if (id_ex_in.valid0) begin
            case ({id_ex_in.alu_op0, id_ex_in.funct3_0})
                // SLT / SLTI（R-type 和 I-type）：funct3=010, alu_op=SUB
                {`ALU_OP_SUB, `FUNCT3_SLT}:
                    corrected_result0 = {31'b0, alu_less0};
                // SLTU / SLTIU（R-type 和 I-type）：funct3=011, alu_op=SUB
                {`ALU_OP_SUB, `FUNCT3_SLTU}:
                    corrected_result0 = {31'b0, alu_less_u0};
                default: ; // 无需修正
            endcase
        end
    end

    always_comb begin
        corrected_result1 = final_result1;

        if (id_ex_in.valid1) begin
            case ({id_ex_in.alu_op1, id_ex_in.funct3_1})
                // SLT / SLTI（R-type 和 I-type）
                {`ALU_OP_SUB, `FUNCT3_SLT}:
                    corrected_result1 = {31'b0, alu_less1};
                // SLTU / SLTIU（R-type 和 I-type）
                {`ALU_OP_SUB, `FUNCT3_SLTU}:
                    corrected_result1 = {31'b0, alu_less_u1};
                default: ;
            endcase
        end
    end

    // ========================================================================
    // JAL 目标寄存器结果：rd = PC + 4
    // ========================================================================
    // JAL：ALU 计算 PC + imm（用于目标地址），但 rd 需要 PC + 4。
    // 我们对 JAL 指令覆盖其结果。

    logic [31:0] jal_result0;
    assign jal_result0 = id_ex_in.jump0 ?
        (id_ex_in.pc0 + 32'd4) : corrected_result0; // JAL/JALR：rd = PC+4

    logic [31:0] jal_result1;
    assign jal_result1 = (id_ex_in.jump1 && !id_ex_in.alu_src1) ?
        (id_ex_in.pc1 + 32'd4) : corrected_result1;

    // ========================================================================
    // EX/MEM 输出组装
    // ========================================================================
    always_comb begin
        // ===== Lane 0 =====
        ex_mem_out.alu_result0   = jal_result0;
        ex_mem_out.rs2_data0     = fwd_b0;       // 存储数据（前推后的 rs2）
        ex_mem_out.rd_addr0      = id_ex_in.rd_addr0;
        ex_mem_out.reg_write0    = id_ex_in.reg_write0 & id_ex_in.valid0;
        ex_mem_out.mem_read0     = id_ex_in.mem_read0 & id_ex_in.valid0;
        ex_mem_out.mem_write0    = id_ex_in.mem_write0 & id_ex_in.valid0;
        ex_mem_out.mem_width0    = id_ex_in.mem_width0;
        ex_mem_out.mem_sign0     = id_ex_in.mem_sign0;
        ex_mem_out.branch_taken0 = branch_taken_internal;
        ex_mem_out.branch_target0= branch_target_calc;
        ex_mem_out.valid0        = id_ex_in.valid0;

        // ===== Lane 1 =====
        ex_mem_out.alu_result1   = jal_result1;
        ex_mem_out.rs2_data1     = fwd_b1;
        ex_mem_out.rd_addr1      = id_ex_in.rd_addr1;
        ex_mem_out.reg_write1    = id_ex_in.reg_write1 & id_ex_in.valid1;
        ex_mem_out.mem_read1     = id_ex_in.mem_read1 & id_ex_in.valid1;
        ex_mem_out.mem_write1    = id_ex_in.mem_write1 & id_ex_in.valid1;
        ex_mem_out.mem_width1    = id_ex_in.mem_width1;
        ex_mem_out.mem_sign1     = id_ex_in.mem_sign1;
        ex_mem_out.branch_taken1 = 1'b0; // Lane 1 不能有分支
        ex_mem_out.branch_target1= 32'b0;
        ex_mem_out.valid1        = id_ex_in.valid1;
    end

endmodule

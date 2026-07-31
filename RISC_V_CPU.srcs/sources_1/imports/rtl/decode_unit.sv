// ============================================================================
// 模块 : decode_unit
// 项目: RISC-V 2发射超标量处理器
// 描述: 双通道指令译码单元，用于2-wide超标量。
//       - 通道0和通道1独立译码
//       - 提取指令字段，生成立即数及控制信号
//       - 强制约束：分支/跳转必须仅在通道0中
//         （若通道0为分支/跳转，通道1强制插入气泡）
//       - 使用4个寄存器文件读端口（每个通道的rs1/rs2）
// ============================================================================

`include "defines.sv"
`include "types.sv"

module decode_unit (
    input  logic        clk,            // 时钟
    input  logic        rst_n,          // 同步复位，低有效

    // ----- 来自IF/ID流水线寄存器的输入 -----
    input  logic [31:0] id_pc0,         // 通道0 PC
    input  logic [31:0] id_inst0,       // 通道0指令字
    input  logic        id_valid0,      // 通道0有效
    input  logic [31:0] id_pc1,         // 通道1 PC
    input  logic [31:0] id_inst1,       // 通道1指令字
    input  logic        id_valid1,      // 通道1有效

    // ----- 来自IF/ID的分支预测信息 -----
    input  logic        id_bp_taken0,   // 通道0分支预测为跳转
    input  logic [31:0] id_bp_target0,  // 通道0预测目标地址

    // ----- 寄存器文件读取数据（4端口） -----
    input  logic [31:0] rf_rs1_data0,   // 通道0 rs1数据（读端口0）
    input  logic [31:0] rf_rs2_data0,   // 通道0 rs2数据（读端口1）
    input  logic [31:0] rf_rs1_data1,   // 通道1 rs1数据（读端口2）
    input  logic [31:0] rf_rs2_data1,   // 通道1 rs2数据（读端口3）

    // ----- 寄存器文件读地址输出（组合逻辑） -----
    output logic [4:0]  rf_rs1_addr0,   // 通道0 rs1地址 -> 读端口0
    output logic [4:0]  rf_rs2_addr0,   // 通道0 rs2地址 -> 读端口1
    output logic [4:0]  rf_rs1_addr1,   // 通道1 rs1地址 -> 读端口2
    output logic [4:0]  rf_rs2_addr1,   // 通道1 rs2地址 -> 读端口3

    // ----- 输出到ID/EX流水线寄存器 -----
    output id_ex_reg_t  id_ex_out        // 双通道译码后的指令信息
);

    // ========================================================================
    // 指令字段提取（组合逻辑）
    // ========================================================================

    // --- 通道0字段 ---
    wire [6:0]  opcode0  = id_inst0[6:0];
    wire [4:0]  rd0      = id_inst0[11:7];
    wire [2:0]  funct3_0 = id_inst0[14:12];
    wire [4:0]  rs1_0    = id_inst0[19:15];
    wire [4:0]  rs2_0    = id_inst0[24:20];
    wire [6:0]  funct7_0 = id_inst0[31:25];

    // --- 通道1字段 ---
    wire [6:0]  opcode1  = id_inst1[6:0];
    wire [4:0]  rd1      = id_inst1[11:7];
    wire [2:0]  funct3_1 = id_inst1[14:12];
    wire [4:0]  rs1_1    = id_inst1[19:15];
    wire [4:0]  rs2_1    = id_inst1[24:20];
    wire [6:0]  funct7_1 = id_inst1[31:25];

    // ========================================================================
    // 寄存器文件读地址
    // ========================================================================
    assign rf_rs1_addr0 = rs1_0;
    assign rf_rs2_addr0 = rs2_0;
    assign rf_rs1_addr1 = rs1_1;
    assign rf_rs2_addr1 = rs2_1;

    // ========================================================================
    // 立即数生成（组合逻辑）
    // ========================================================================

    // --- 通道0立即数 ---
    logic [31:0] imm0;
    always_comb begin
        case (opcode0)
            `OPCODE_LUI, `OPCODE_AUIPC: // U类型
                imm0 = {id_inst0[31:12], 12'b0};
            `OPCODE_JAL:                 // J类型
                imm0 = {{11{id_inst0[31]}}, id_inst0[31], id_inst0[19:12],
                         id_inst0[20], id_inst0[30:21], 1'b0};
            `OPCODE_JALR, `OPCODE_LOAD, `OPCODE_ALU_IMM: // I类型
                imm0 = {{20{id_inst0[31]}}, id_inst0[31:20]};
            `OPCODE_STORE:               // S类型
                imm0 = {{20{id_inst0[31]}}, id_inst0[31:25], id_inst0[11:7]};
            `OPCODE_BRANCH:              // B类型
                imm0 = {{19{id_inst0[31]}}, id_inst0[31], id_inst0[7],
                         id_inst0[30:25], id_inst0[11:8], 1'b0};
            default:
                imm0 = 32'b0;
        endcase
    end

    // --- 通道1立即数 ---
    logic [31:0] imm1;
    always_comb begin
        case (opcode1)
            `OPCODE_LUI, `OPCODE_AUIPC:
                imm1 = {id_inst1[31:12], 12'b0};
            `OPCODE_JAL:
                imm1 = {{11{id_inst1[31]}}, id_inst1[31], id_inst1[19:12],
                         id_inst1[20], id_inst1[30:21], 1'b0};
            `OPCODE_JALR, `OPCODE_LOAD, `OPCODE_ALU_IMM:
                imm1 = {{20{id_inst1[31]}}, id_inst1[31:20]};
            `OPCODE_STORE:
                imm1 = {{20{id_inst1[31]}}, id_inst1[31:25], id_inst1[11:7]};
            `OPCODE_BRANCH:
                imm1 = {{19{id_inst1[31]}}, id_inst1[31], id_inst1[7],
                         id_inst1[30:25], id_inst1[11:8], 1'b0};
            default:
                imm1 = 32'b0;
        endcase
    end

    // ========================================================================
    // 控制信号生成 - 通道0
    // ========================================================================
    logic [2:0]  alu_op0;
    logic        alu_src0, reg_write0, mem_read0, mem_write0;
    logic [2:0]  mem_width0;
    logic        mem_sign0, branch0, jump0, auipc0, lui0;

    always_comb begin
        alu_op0     = `ALU_OP_ADD;
        alu_src0    = 1'b0;
        reg_write0  = 1'b0;
        mem_read0   = 1'b0;
        mem_write0  = 1'b0;
        mem_width0  = 3'b010;
        mem_sign0   = 1'b1;
        branch0     = 1'b0;
        jump0       = 1'b0;
        auipc0      = 1'b0;
        lui0        = 1'b0;

        case (opcode0)
            `OPCODE_ALU: begin
                reg_write0 = 1'b1;
                case (funct3_0)
                    `FUNCT3_ADD_SUB: alu_op0 = (funct7_0[5]) ? `ALU_OP_SUB : `ALU_OP_ADD;
                    `FUNCT3_SLL:     alu_op0 = `ALU_OP_SLL;
                    `FUNCT3_SLT:     alu_op0 = `ALU_OP_SUB;
                    `FUNCT3_SLTU:    alu_op0 = `ALU_OP_SUB;
                    `FUNCT3_XOR:     alu_op0 = `ALU_OP_XOR;
                    `FUNCT3_SRL_SRA: alu_op0 = (funct7_0[5]) ? `ALU_OP_SRA : `ALU_OP_SRL;
                    `FUNCT3_OR:      alu_op0 = `ALU_OP_OR;
                    `FUNCT3_AND:     alu_op0 = `ALU_OP_AND;
                    default:         alu_op0 = `ALU_OP_ADD;
                endcase
            end
            `OPCODE_ALU_IMM: begin
                reg_write0 = 1'b1;
                alu_src0   = 1'b1;
                case (funct3_0)
                    `FUNCT3_ADD_SUB: alu_op0 = `ALU_OP_ADD;
                    `FUNCT3_SLL:     alu_op0 = `ALU_OP_SLL;
                    `FUNCT3_SLT:     alu_op0 = `ALU_OP_SUB;
                    `FUNCT3_SLTU:    alu_op0 = `ALU_OP_SUB;
                    `FUNCT3_XOR:     alu_op0 = `ALU_OP_XOR;
                    `FUNCT3_SRL_SRA: alu_op0 = (funct7_0[5]) ? `ALU_OP_SRA : `ALU_OP_SRL;
                    `FUNCT3_OR:      alu_op0 = `ALU_OP_OR;
                    `FUNCT3_AND:     alu_op0 = `ALU_OP_AND;
                    default:         alu_op0 = `ALU_OP_ADD;
                endcase
            end
            `OPCODE_LOAD: begin
                reg_write0 = 1'b1;
                mem_read0  = 1'b1;
                alu_src0   = 1'b1;
                mem_width0 = funct3_0;
                mem_sign0  = ~funct3_0[2];
            end
            `OPCODE_STORE: begin
                mem_write0 = 1'b1;
                alu_src0   = 1'b1;
                mem_width0 = funct3_0;
            end
            `OPCODE_BRANCH: begin
                branch0 = 1'b1;
                alu_op0 = `ALU_OP_SUB;
            end
            `OPCODE_JAL: begin
                reg_write0 = 1'b1;
                jump0      = 1'b1;
            end
            `OPCODE_JALR: begin
                reg_write0 = 1'b1;
                jump0      = 1'b1;
                alu_src0   = 1'b1;
            end
            `OPCODE_LUI: begin
                reg_write0 = 1'b1;
                alu_op0    = `ALU_OP_OR;
                alu_src0   = 1'b1;
                lui0       = 1'b1;
            end
            `OPCODE_AUIPC: begin
                reg_write0 = 1'b1;
                alu_src0   = 1'b1;
                auipc0     = 1'b1;
            end
            default: ; // NOP / FENCE / 未知指令
        endcase
    end

    // ========================================================================
    // 控制信号生成 - 通道1
    // ========================================================================
    logic [2:0]  alu_op1;
    logic        alu_src1, reg_write1, mem_read1, mem_write1;
    logic [2:0]  mem_width1;
    logic        mem_sign1, branch1, jump1, auipc1, lui1;

    always_comb begin
        alu_op1     = `ALU_OP_ADD;
        alu_src1    = 1'b0;
        reg_write1  = 1'b0;
        mem_read1   = 1'b0;
        mem_write1  = 1'b0;
        mem_width1  = 3'b010;
        mem_sign1   = 1'b1;
        branch1     = 1'b0;
        jump1       = 1'b0;
        auipc1      = 1'b0;
        lui1        = 1'b0;

        case (opcode1)
            `OPCODE_ALU: begin
                reg_write1 = 1'b1;
                case (funct3_1)
                    `FUNCT3_ADD_SUB: alu_op1 = (funct7_1[5]) ? `ALU_OP_SUB : `ALU_OP_ADD;
                    `FUNCT3_SLL:     alu_op1 = `ALU_OP_SLL;
                    `FUNCT3_SLT:     alu_op1 = `ALU_OP_SUB;
                    `FUNCT3_SLTU:    alu_op1 = `ALU_OP_SUB;
                    `FUNCT3_XOR:     alu_op1 = `ALU_OP_XOR;
                    `FUNCT3_SRL_SRA: alu_op1 = (funct7_1[5]) ? `ALU_OP_SRA : `ALU_OP_SRL;
                    `FUNCT3_OR:      alu_op1 = `ALU_OP_OR;
                    `FUNCT3_AND:     alu_op1 = `ALU_OP_AND;
                    default:         alu_op1 = `ALU_OP_ADD;
                endcase
            end
            `OPCODE_ALU_IMM: begin
                reg_write1 = 1'b1;
                alu_src1   = 1'b1;
                case (funct3_1)
                    `FUNCT3_ADD_SUB: alu_op1 = `ALU_OP_ADD;
                    `FUNCT3_SLL:     alu_op1 = `ALU_OP_SLL;
                    `FUNCT3_SLT:     alu_op1 = `ALU_OP_SUB;
                    `FUNCT3_SLTU:    alu_op1 = `ALU_OP_SUB;
                    `FUNCT3_XOR:     alu_op1 = `ALU_OP_XOR;
                    `FUNCT3_SRL_SRA: alu_op1 = (funct7_1[5]) ? `ALU_OP_SRA : `ALU_OP_SRL;
                    `FUNCT3_OR:      alu_op1 = `ALU_OP_OR;
                    `FUNCT3_AND:     alu_op1 = `ALU_OP_AND;
                    default:         alu_op1 = `ALU_OP_ADD;
                endcase
            end
            `OPCODE_LOAD: begin
                reg_write1 = 1'b1;
                mem_read1  = 1'b1;
                alu_src1   = 1'b1;
                mem_width1 = funct3_1;
                mem_sign1  = ~funct3_1[2];
            end
            `OPCODE_STORE: begin
                mem_write1 = 1'b1;
                alu_src1   = 1'b1;
                mem_width1 = funct3_1;
            end
            `OPCODE_BRANCH: begin
                branch1 = 1'b1;
                alu_op1 = `ALU_OP_SUB;
            end
            `OPCODE_JAL: begin
                reg_write1 = 1'b1;
                jump1      = 1'b1;
            end
            `OPCODE_JALR: begin
                reg_write1 = 1'b1;
                jump1      = 1'b1;
                alu_src1   = 1'b1;
            end
            `OPCODE_LUI: begin
                reg_write1 = 1'b1;
                alu_op1    = `ALU_OP_OR;
                alu_src1   = 1'b1;
                lui1       = 1'b1;
            end
            `OPCODE_AUIPC: begin
                reg_write1 = 1'b1;
                alu_src1   = 1'b1;
                auipc1     = 1'b1;
            end
            default: ;
        endcase
    end

    // ========================================================================
    // 超标量约束：仅条件分支强制通道1插入气泡
    // - 分支（条件）：通道1必须进入气泡（控制流不确定性）
    // - JAL/JALR：通道1可以执行（无条件，无控制冒险）
    // - Load/Store：两个通道均可访问内存（双端口数据存储器）
    // ========================================================================
    logic lane0_is_branch;
    assign lane0_is_branch = branch0;

    logic eff_valid1;
    assign eff_valid1 = id_valid1 & ~lane0_is_branch;

    // ========================================================================
    // 输出组装：将译码信息打包进 id_ex_reg_t
    // ========================================================================
    always_comb begin
        // ===== 通道0 =====
        id_ex_out.pc0         = id_pc0;
        id_ex_out.rd_addr0    = rd0;
        id_ex_out.rs1_data0   = rf_rs1_data0;   // rs1来自读端口0
        id_ex_out.rs2_data0   = rf_rs2_data0;   // rs2来自读端口1
        id_ex_out.imm0        = imm0;
        id_ex_out.alu_op0     = alu_op0;
        id_ex_out.alu_src0    = alu_src0;
        id_ex_out.reg_write0  = reg_write0 & id_valid0;
        id_ex_out.mem_read0   = mem_read0 & id_valid0;
        id_ex_out.mem_write0  = mem_write0 & id_valid0;
        id_ex_out.mem_width0  = mem_width0;
        id_ex_out.mem_sign0   = mem_sign0;
        id_ex_out.branch0     = branch0 & id_valid0;
        id_ex_out.jump0       = jump0 & id_valid0;
        id_ex_out.auipc0      = auipc0 & id_valid0;
        id_ex_out.lui0        = lui0 & id_valid0;
        id_ex_out.funct3_0    = funct3_0;
        id_ex_out.rs1_addr0   = rs1_0;
        id_ex_out.rs2_addr0   = rs2_0;
        id_ex_out.valid0      = id_valid0;

        // ===== 通道1 =====
        id_ex_out.pc1         = id_pc1;
        id_ex_out.rd_addr1    = rd1;
        id_ex_out.rs1_data1   = rf_rs1_data1;   // rs1来自读端口2
        id_ex_out.rs2_data1   = rf_rs2_data1;   // rs2来自读端口3
        id_ex_out.imm1        = imm1;
        id_ex_out.alu_op1     = alu_op1;
        id_ex_out.alu_src1    = alu_src1;
        id_ex_out.reg_write1  = reg_write1 & eff_valid1;
        id_ex_out.mem_read1   = mem_read1 & eff_valid1;
        id_ex_out.mem_write1  = mem_write1 & eff_valid1;
        id_ex_out.mem_width1  = mem_width1;
        id_ex_out.mem_sign1   = mem_sign1;
        id_ex_out.branch1     = branch1 & eff_valid1;
        id_ex_out.jump1       = jump1 & eff_valid1;
        id_ex_out.auipc1      = auipc1 & eff_valid1;
        id_ex_out.lui1        = lui1 & eff_valid1;
        id_ex_out.funct3_1    = funct3_1;
        id_ex_out.rs1_addr1   = rs1_1;
        id_ex_out.rs2_addr1   = rs2_1;
        id_ex_out.valid1      = eff_valid1;

        // ===== 分支预测信息 =====
        id_ex_out.bp_taken0   = id_bp_taken0;
        id_ex_out.bp_target0  = id_bp_target0;
    end

endmodule

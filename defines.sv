`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/08 12:42:16
// Design Name: 
// Module Name: defines
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: RISC-V指令集定义文件
//              定义各种指令类型的opcode常量
//              用于指令解码和类型判断
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//`define RUN_TRACE  // 运行跟踪宏（已注释）

// RISC-V RV32I指令类型opcode定义
`define R_TYPE   7'b011_0011  // R型指令：寄存器-寄存器操作（add, sub, and, or等）
`define I_TYPE   7'b001_0011  // I型指令：立即数操作（addi, andi, ori等）
`define IL_TYPE  7'b000_0011  // 加载指令：从存储器读取（lw, lb, lh等）
`define IJ_TYPE  7'b110_0111  // JALR指令：寄存器间接跳转
`define S_TYPE   7'b010_0011  // 存储指令：写入存储器（sw, sb, sh等）
`define B_TYPE   7'b110_0011  // 分支指令：条件分支（beq, bne, blt等）
`define U_TYPE   7'b011_0111  // LUI指令：加载高位立即数
`define UA_TYPE  7'b001_0111  // AUIPC指令：PC相对地址计算
`define J_TYPE   7'b110_1111  // JAL指令：直接跳转
`define CSR_TYPE 7'b111_0011  // CSR指令：控制和状态寄存器操作

`define OPCODE_LEN 7  // opcode长度（7位）

// NPC操作类型定义 (2-bit)
`define NPC_OP_ADD4   2'b00  // 顺序执行：PC+4
`define NPC_OP_BRANCH 2'b01  // 条件分支
`define NPC_OP_JALR   2'b10  // 寄存器间接跳转（JALR）
`define NPC_OP_JAL    2'b11  // 直接跳转（JAL）

// MemToReg 信号定义 (3-bit)
// 000: pcadd4, 001: ALU结果, 010: 存储器数据, 011: 立即数, 100: CSR数据
`define MEM_TO_REG_PCADD4 3'b000
`define MEM_TO_REG_ALU    3'b001
`define MEM_TO_REG_MEM    3'b010
`define MEM_TO_REG_IMM    3'b011
`define MEM_TO_REG_CSR    3'b100

// OffsetOrigin 信号定义 (2-bit)
// 00: 立即数, 01: ALU结果, 10: CSR计算的NPC
`define OFFSET_ORIGIN_IMM       2'b00
`define OFFSET_ORIGIN_ALU       2'b01
`define OFFSET_ORIGIN_CSR_NPC   2'b10

// CSR指令 funct3 定义
`define CSR_FUNCT3_RW    3'b001  // csrrw
`define CSR_FUNCT3_RS    3'b010  // csrrs
`define CSR_FUNCT3_RC    3'b011  // csrrc
`define CSR_FUNCT3_RWI   3'b101  // csrrwi
`define CSR_FUNCT3_RSI   3'b110  // csrrsi
`define CSR_FUNCT3_RCI   3'b111  // csrrci
`define CSR_FUNCT3_PRIV  3'b000  // ecall, mret, etc.

// Mask单元加载类型定义 (3-bit)
`define MASK_LB   3'b000  // lb/lbu: 字节加载
`define MASK_LH   3'b001  // lh/lhu: 半字加载
`define MASK_LW   3'b010  // lw: 字加载

// CSR 寄存器地址定义
`define CSR_MSTATUS   12'h300  // Machine Status Register
`define CSR_MTVEC     12'h305  // Machine Trap-Vector Base-Address Register
`define CSR_MEPC      12'h341  // Machine Exception Program Counter
`define CSR_MCAUSE    12'h342  // Machine Cause Register

// CSR 控制信号定义 (对应 CCTL 输出的 CSRControll)
// 注意：这些值需与 CCTL 模块生成的控制信号保持一致
`define CSR_CTRL_NOP    4'b0000  // 无操作/保持
`define CSR_CTRL_RS     4'b0001  // Read and Set (csrrs)
`define CSR_CTRL_RW     4'b0010  // Read and Write (csrrw)
`define CSR_CTRL_ECALL  4'b0100  // Environment Call (ecall)
`define CSR_CTRL_MRET   4'b1000  // Machine Return (mret)

//`endif

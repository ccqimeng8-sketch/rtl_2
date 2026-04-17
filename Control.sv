`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/30 8:26:09
// Design Name: 
// Module Name: Control
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 控制单元（Control Unit）模块
//              根据指令的opcode和funct字段生成CPU控制信号
//              控制数据通路中各个模块的操作
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module Control(
    input  logic [6:0]  opcode      ,  // 指令操作码（7位）
    input  logic [2:0]  funct       ,  // 指令功能码（3位，funct3）
    output logic [1:0]  NpcOp       ,  // NPC操作选择（2位）
    output logic        RegWrite    ,  // 寄存器写使能
    output logic [2:0]  MemToReg    ,  // 写回数据源选择（3位）
    output logic        MemWrite    ,  // 存储器写使能
    output logic [1:0]  OffsetOrigin,  // 偏移量来源选择（2位）
    output logic        ALUSrcA     ,  // ALU操作数A来源选择
    output logic        ALUSrcB      // ALU操作数B来源选择
);
    // 指令类型解码信号
    logic op_jalr, op_branch, op_jal, op_store, op_rtype, op_itype, op_load, op_auipc, op_lui, op_csr, op_call_ret;

    // 根据opcode判断指令类型
    assign op_jalr = opcode == `IJ_TYPE;      // 寄存器间接跳转（jalr）
    assign op_branch = opcode == `B_TYPE;     // 条件分支指令
    assign op_jal = opcode == `J_TYPE;        // 直接跳转指令（jal）
    assign op_store = opcode == `S_TYPE;      // 存储指令
    assign op_rtype = opcode == `R_TYPE;      // R型指令
    assign op_itype = opcode == `I_TYPE;      // I型指令
    assign op_load = opcode == `IL_TYPE;      // 加载指令
    assign op_auipc = opcode == `UA_TYPE;     // AUIPC指令
    assign op_lui = opcode == `U_TYPE;        // LUI指令
    assign op_csr = (opcode == `CSR_TYPE) && (funct[2:0] != `CSR_FUNCT3_PRIV);   // CSR读写指令
    assign op_call_ret = (opcode == `CSR_TYPE) && (funct[2:0] == `CSR_FUNCT3_PRIV);  // ecall/mret

    // NPC操作选择：决定下一条指令地址的计算方式
    // 00: PC+4（顺序执行），01: 分支，10: JALR/返回，11: JAL
    assign NpcOp = {2{op_jalr}} & `NPC_OP_JALR |
                {2{op_call_ret}} & `NPC_OP_JALR |
                {2{op_branch}} & `NPC_OP_BRANCH |
                {2{op_jal}} & `NPC_OP_JAL;
    
    // 寄存器写使能：分支、存储、ecall/mret指令不写寄存器
    assign RegWrite = ~(op_branch | op_store | op_call_ret);
    
    // 写回数据源选择：决定写入寄存器的数据来源
    // 000: pcadd4, 001: ALU结果, 010: 存储器数据, 011: 立即数, 100: CSR数据
    assign MemToReg = {3{op_rtype}} & `MEM_TO_REG_ALU |
                    {3{op_itype}} & `MEM_TO_REG_ALU | 
                    {3{op_auipc}} & `MEM_TO_REG_ALU | 
                    {3{op_load}} & `MEM_TO_REG_MEM |
                    {3{op_lui}} & `MEM_TO_REG_IMM |
                    {3{op_csr}} & `MEM_TO_REG_CSR;
    
    // 存储器写使能：仅存储指令需要写存储器
    assign MemWrite = op_store;
    
    // 偏移量来源选择：决定offset的来源
    // 00: 立即数，01: ALU结果，10: CSR计算的NPC
    assign OffsetOrigin = {2{op_jalr}} & `OFFSET_ORIGIN_ALU | {2{op_call_ret}} & `OFFSET_ORIGIN_CSR_NPC;
    
    // ALU操作数A来源：AUIPC指令使用PC，其他使用寄存器值
    assign ALUSrcA = op_auipc;
    
    // ALU操作数B来源：R型和分支指令使用寄存器值，其他使用立即数
    assign ALUSrcB = ~(op_rtype | op_branch);


endmodule

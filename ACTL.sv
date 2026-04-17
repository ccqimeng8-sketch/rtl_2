`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/03 11:25:24
// Design Name: 
// Module Name: ACTL
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: ALU控制单元（ALU Control Unit）模块
//              根据指令的opcode和funct字段生成ALU控制信号
//              支持RISC-V RV32I基本整数指令集的所有ALU操作
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.sv"

module ACTL(
    input  logic [6:0] opcode       ,  // 指令操作码（7位）
    input  logic [3:0] funct        ,  // 指令功能码（4位，包含funct3和funct7的部分位）
    output logic [13:0] ALUControl     // ALU控制信号（14位独热码）
);
    // ALU操作类型定义（14位独热码编码）
    localparam ADD      = 14'h0001;  // 加法
    localparam SUB      = 14'h0002;  // 减法
    localparam AND      = 14'h0004;  // 按位与
    localparam OR       = 14'h0008;  // 按位或
    localparam XOR      = 14'h0010;  // 按位异或
    localparam SLL      = 14'h0020;  // 逻辑左移
    localparam SRL      = 14'h0040;  // 逻辑右移
    localparam SRA      = 14'h0080;  // 算术右移
    localparam BEQ      = 14'h0100;  // 相等分支
    localparam BNE      = 14'h0200;  // 不等分支
    localparam BLT      = 14'h0400;  // 有符号小于分支
    localparam BGE      = 14'h0800;  // 有符号大于等于分支
    localparam BGEU     = 14'h1000;  // 无符号大于等于分支
    localparam BLTU     = 14'h2000;  // 无符号小于分支

    localparam ERR      = 14'h0;     // 错误操作码

    // ALU操作使能信号（内部信号）
    logic op_add, op_sub, op_and, op_or, op_xor, op_sll, op_srl;
    logic op_sra, op_beq, op_bne, op_blt, op_bge, op_bgeu, op_bltu;

    // ALU控制信号生成：使用独热码选择对应的ALU操作
    // 每个操作信号扩展为14位后与对应的操作码进行与运算，最后通过或运算合并
    assign ALUControl = {14{op_add}} & ADD |
                        {14{op_sub}} & SUB |
                        {14{op_and}} & AND |
                        {14{op_or}} & OR |
                        {14{op_xor}} & XOR |
                        {14{op_sll}} & SLL |
                        {14{op_srl}} & SRL |
                        {14{op_sra}} & SRA |
                        {14{op_beq}} & BEQ |
                        {14{op_bne}} & BNE |
                        {14{op_blt}} & BLT |
                        {14{op_bge}} & BGE |
                        {14{op_bgeu}} & BGEU |
                        {14{op_bltu}} & BLTU;

    // 指令类型解码信号
    logic rtype, itype, load, store, jalr, auipc, branch;

    // 根据opcode判断指令类型
    assign rtype = opcode == `R_TYPE;   // R型指令（寄存器-寄存器操作）
    assign itype = opcode == `I_TYPE;   // I型指令（立即数操作）
    assign load = opcode == `IL_TYPE;   // 加载指令（lw, lb, lh等）
    assign store = opcode == `S_TYPE;   // 存储指令（sw, sb, sh等）
    assign jalr = opcode == `IJ_TYPE;   // 寄存器间接跳转（jalr）
    assign auipc = opcode == `UA_TYPE;  // PC相对地址计算（auipc）
    assign branch = opcode == `B_TYPE;  // 分支指令（beq, bne等）

    // ALU操作译码逻辑：根据指令类型和funct字段确定具体操作
    
    // 加法操作：R型(funct=0000)、I型、加载、存储、AUIPC、JALR
    assign op_add = (rtype && funct == 4'b0000) ||
                    (itype && funct[2:0] == 3'b000) ||
                    (load && funct[2:0] == 3'b000) ||
                    (load && funct[2:0] == 3'b001) ||
                    (load && funct[2:0] == 3'b010) ||
                    (load && funct[2:0] == 3'b100) ||
                    (load && funct[2:0] == 3'b101) ||
                    (store && funct[2:0] == 3'b000) ||
                    (store && funct[2:0] == 3'b001) ||
                    (store && funct[2:0] == 3'b010) ||
                    auipc || (jalr && funct[2:0] == 3'b000);
    
    // 减法操作：仅R型指令(funct=1000)
    assign op_sub = (rtype && funct == 4'b1000);
    
    // 按位与操作：R型和I型指令
    assign op_and = (rtype && funct == 4'b0111) || (itype && funct[2:0] == 3'b111);
    
    // 按位或操作：R型和I型指令
    assign op_or = (rtype && funct == 4'b0110) || (itype && funct[2:0] == 3'b110);
    
    // 按位异或操作：R型和I型指令
    assign op_xor = (rtype && funct == 4'b0100) || (itype && funct[2:0] == 3'b100);
    
    // 逻辑左移：R型和I型指令(funct=0001)
    assign op_sll = (rtype || itype) && funct == 4'b0001;
    
    // 逻辑右移：R型和I型指令(funct=0101)
    assign op_srl = (rtype || itype) && funct == 4'b0101;
    
    // 算术右移：R型和I型指令(funct=1101)
    assign op_sra = (rtype || itype) && funct == 4'b1101;
    
    // 无符号小于比较：用于BLTU指令
    assign op_bltu = (rtype && funct == 4'b0011) || (branch && funct[2:0] == 3'b110) || (itype && funct[2:0] == 3'b011);
    
    // 有符号小于比较：用于BLT指令
    assign op_blt = (rtype && funct == 4'b0010) || (branch && funct[2:0] == 3'b100) || (itype && funct[2:0] == 3'b010);
    
    // 分支指令的比较操作
    assign op_beq = branch && funct[2:0] == 3'b000;   // 相等比较
    assign op_bne = branch && funct[2:0] == 3'b001;   // 不等比较
    assign op_bge = branch && funct[2:0] == 3'b101;   // 有符号大于等于比较
    assign op_bgeu = branch && funct[2:0] == 3'b111;  // 无符号大于等于比较
endmodule
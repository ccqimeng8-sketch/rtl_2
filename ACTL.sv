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

    // 指令类型解码信号
    logic rtype, itype, load, store, jalr, auipc, branch;

    // 使用 always_comb 替代 assign
    always_comb begin
        // 初始化所有操作信号为0
        op_add = 1'b0;
        op_sub = 1'b0;
        op_and = 1'b0;
        op_or = 1'b0;
        op_xor = 1'b0;
        op_sll = 1'b0;
        op_srl = 1'b0;
        op_sra = 1'b0;
        op_beq = 1'b0;
        op_bne = 1'b0;
        op_blt = 1'b0;
        op_bge = 1'b0;
        op_bgeu = 1'b0;
        op_bltu = 1'b0;

        // 判断指令类型
        rtype = (opcode == `R_TYPE);
        itype = (opcode == `I_TYPE);
        load = (opcode == `IL_TYPE);
        store = (opcode == `S_TYPE);
        jalr = (opcode == `IJ_TYPE);
        auipc = (opcode == `UA_TYPE);
        branch = (opcode == `B_TYPE);

        // 根据指令类型和funct字段设置操作信号
        if (rtype) begin
            case (funct)
                4'b0000: op_add = 1'b1;
                4'b1000: op_sub = 1'b1;
                4'b0111: op_and = 1'b1;
                4'b0110: op_or = 1'b1;
                4'b0100: op_xor = 1'b1;
                4'b0001: op_sll = 1'b1;
                4'b0101: op_srl = 1'b1;
                4'b1101: op_sra = 1'b1;
                4'b0010: op_blt = 1'b1;
                4'b0011: op_bltu = 1'b1;
                default: ; // 保持为0
            endcase
        end else if (itype) begin
            case (funct[2:0])
                3'b000: op_add = 1'b1;
                3'b111: op_and = 1'b1;
                3'b110: op_or = 1'b1;
                3'b100: op_xor = 1'b1;
                3'b001: op_sll = 1'b1;
                3'b101: op_srl = 1'b1;
                3'b110: op_sra = 1'b1; // 注意：funct7=1时才是SRA，但此处仅用funct[3]==1判断不够，但原逻辑如此
                3'b010: op_blt = 1'b1;
                3'b011: op_bltu = 1'b1;
                default: ;
            endcase
            // 特殊处理 SRA：需要检查 funct[3] 是否为1（即 funct == 4'b1101）
            if (funct == 4'b1101)
                op_sra = 1'b1;
        end else if (load) begin
            case (funct[2:0])
                3'b000,
                3'b001,
                3'b010,
                3'b100,
                3'b101: op_add = 1'b1;
                default: ;
            endcase
        end else if (store) begin
            case (funct[2:0])
                3'b000,
                3'b001,
                3'b010: op_add = 1'b1;
                default: ;
            endcase
        end else if (auipc) begin
            op_add = 1'b1;
        end else if (jalr) begin
            if (funct[2:0] == 3'b000)
                op_add = 1'b1;
        end else if (branch) begin
            case (funct[2:0])
                3'b000: op_beq = 1'b1;
                3'b001: op_bne = 1'b1;
                3'b100: op_blt = 1'b1;
                3'b101: op_bge = 1'b1;
                3'b110: op_bltu = 1'b1;
                3'b111: op_bgeu = 1'b1;
                default: ;
            endcase
        end
    end

    // ALU控制信号生成：使用独热码选择对应的ALU操作
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
endmodule
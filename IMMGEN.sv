`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/18 11:22:17
// Design Name: 
// Module Name: IMMGEN
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 立即数生成器（Immediate Generator）模块
//              根据指令类型从指令字中提取并符号扩展立即数
//              支持RISC-V所有指令格式的立即数编码
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.sv"

module IMMGEN#(
    parameter   DATAWIDTH = 32	  // 数据宽度，默认为32位
)(
    input  logic [DATAWIDTH-1:0]   instr   ,  // 指令字（32位）
    output logic [DATAWIDTH - 1:0] imm        // 生成的立即数（32位）
);
    // 指令类型解码信号
    logic op_itype, op_stype, op_btype, op_utype, op_jtype;
    logic [6:0] opcode;

    // 提取指令的opcode字段
    assign opcode = instr[6:0];

    // 根据opcode判断指令类型
    assign op_itype = (opcode == `I_TYPE)   // I型：addi, andi等
        || (opcode == `IL_TYPE)             // 加载指令：lw, lb, lh等
        || (opcode == `IJ_TYPE);            // JALR指令
    assign op_stype = opcode == `S_TYPE;    // S型：存储指令（sw, sb, sh等）
    assign op_btype = opcode == `B_TYPE;    // B型：分支指令（beq, bne等）
    assign op_utype = (opcode == `U_TYPE) || (opcode == `UA_TYPE);  // U型：LUI, AUIPC
    assign op_jtype = opcode == `J_TYPE;    // J型：JAL指令

    // 立即数生成：根据指令类型从不同位段提取并拼接
    // I型：instr[31:20]，符号扩展
    // S型：instr[31:25]和instr[11:7]，符号扩展
    // B型：instr[31],instr[7],instr[30:25],instr[11:8]，左移1位，符号扩展
    // U型：instr[31:12]，左移12位
    // J型：instr[31],instr[19:12],instr[20],instr[30:21]，左移1位，符号扩展
    assign imm = {32{op_itype}} & {{20{instr[31]}}, instr[31:20]} |
                {32{op_stype}} & {{20{instr[31]}}, instr[31:25], instr[11:7]} |
                {32{op_btype}} & {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0} |
                {32{op_utype}} & {instr[31:12], 12'b0} |
                {32{op_jtype}} & {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

endmodule
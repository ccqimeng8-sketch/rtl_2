`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/23 12:42:16
// Design Name: 
// Module Name: NPC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 下一程序计数器（Next Program Counter）模块
//              根据当前PC和控制信号计算下一条指令的地址
//              支持顺序执行、分支、JAL、JALR等跳转方式
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module NPC#(
    parameter   DATAWIDTH = 32  // 数据宽度，默认为32位
)(

    input  logic                   isTrue   ,  // 分支条件判断结果
    input  logic [1:0]             npc_op   ,  // NPC操作选择（2位）
    input  logic [DATAWIDTH - 1:0] pc       ,  // 当前PC值
    input  logic [DATAWIDTH - 1:0] offset   ,  // 偏移量
    output logic [DATAWIDTH - 1:0] npc      ,  // 下一条指令地址
    output logic [DATAWIDTH - 1:0] pcadd4    // PC+4的结果
);
    
    // NPC操作类型解码
    logic op_branch, op_add4, op_jalr, op_jal;
    logic [DATAWIDTH-1:0] branch_addr, jalr_addr, jal_addr;

    // 根据npc_op解码操作类型
    assign op_add4 = npc_op == `NPC_OP_ADD4;   // 顺序执行：PC+4
    assign op_branch = npc_op == `NPC_OP_BRANCH; // 条件分支
    assign op_jalr = npc_op == `NPC_OP_JALR;   // 寄存器间接跳转（JALR）
    assign op_jal = npc_op == `NPC_OP_JAL;    // 直接跳转（JAL）

    // 各类跳转地址计算
    // 分支地址：条件满足时跳转到pc+offset，否则顺序执行pc+4
    assign branch_addr = isTrue ? (pc + offset) : (pc + 4);
    
    // JALR地址：offset的最低位清零（保证字对齐）
    assign jalr_addr = offset & {{DATAWIDTH - 1{1'b1}}, 1'b0};
    
    // JAL地址：pc + offset
    assign jal_addr = pc + offset;
    
    // 最终NPC选择：根据操作类型选择对应的地址
    assign npc = {32{op_add4}} & pcadd4 |
            {32{op_branch}} & branch_addr |
            {32{op_jalr}} & jalr_addr |
            {32{op_jal}} & jal_addr;

    // PC+4计算：顺序执行的下一条指令地址
    assign pcadd4 = pc + 4;
endmodule
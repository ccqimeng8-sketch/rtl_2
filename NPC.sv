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
    input  logic predict_taken              ,  // 分支预测结果
    output logic [DATAWIDTH - 1:0] npc      ,  // 下一条指令地址
    output logic [DATAWIDTH - 1:0] pcadd4    // PC+4的结果
);

    assign pcadd4 = pc + 4;

    // 使用 always_comb 替代所有带判断的 assign
    always_comb begin
        // 初始化输出，避免 latch
        npc = pcadd4; // 默认顺序执行

        case (npc_op)
            `NPC_OP_ADD4: begin
                npc = pcadd4;
            end
            `NPC_OP_BRANCH: begin
                if (predict_taken) begin
                    npc = pc + offset;  // 预测跳转
                end else begin
                    npc = pcadd4;  // 预测不跳
                end
            end
            `NPC_OP_JALR: begin
                // JALR: offset 最低位清零（字对齐）
                npc = offset & {{DATAWIDTH - 1{1'b1}}, 1'b0};
            end
            `NPC_OP_JAL: begin
                npc = pc + offset;
            end
            default: begin
                npc = pcadd4;
            end
        endcase
    end

endmodule

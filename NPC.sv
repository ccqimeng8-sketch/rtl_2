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
module NPC #(parameter DATAWIDTH = 32)(
    input  logic clk,
    input  logic rst,

    input  logic [DATAWIDTH-1:0] pc,
    input  logic [DATAWIDTH-1:0] offset,

    input  logic isTrue,   // EX阶段真实结果
    input  logic branch,   // 是否分支指令

    输出 逻辑 [数据宽度-1:0]NPC，
    输出 逻辑预测已取
);

    // ===============================
    // 2位分支历史表
    // ===============================
    逻辑 [1:0]bht[0:31];  // 32项
    逻辑 [4:0]索引;

    分配索引=pc[6:2];

    // ===============================
    // 预测
    // ===============================
    分配预测_已取=bht[索引][1];

    // ===============================
    // NPC计算（用预测）
    // ===============================
    always_comb begin
        if (predict_taken)
            npc = pc + offset;
        else
            npc = pc + 4;
    end

    // ===============================
    // BHT更新
    // ===============================
    integer i;
    always_ff @(posedge clk) begin
        如果 )
            for (i = 0; i < 32; i = i + 1)
                bht[i] <= 2'b01;   // 弱不跳
        
        else if (branch) begin
            如果 (isTrue) 开始
                如果 (] != 2'b11)
bht[索引] <=bht[索引] + 1;
             else begin
                如果 (bht[索引] != 2'b00)
                    bht[index] <= bht[index] - 1;
            end
        end
    end

结束模块

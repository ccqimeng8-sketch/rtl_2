`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/08 12:42:16
// Design Name: 
// Module Name: PC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 程序计数器（Program Counter）模块
//              用于存储和更新当前执行指令的地址
//              在复位时初始化为RESET_VAL指定的地址
//              每个时钟周期更新为下一个指令地址(npc)
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module PC#(
    parameter   DATAWIDTH   = 32              ,  // 数据宽度，默认为32位
    parameter   RESET_VAL   = 32'h8000_0000      // 复位时的初始PC值，默认为0x8000_0000
)(
    input  logic                   clk  ,       // 时钟信号
    input  logic                   rst,         // 复位信号，高电平有效
    input  logic [DATAWIDTH - 1:0] npc  ,       // 下一个PC值（next program counter）
    output logic [DATAWIDTH - 1:0] pc_out        // 当前PC值输出
);
    logic [DATAWIDTH - 1:0] reg_pc;             // PC寄存器，存储当前程序计数值
    logic rst_delay;                            // 复位延迟信号，用于同步复位
/*
    // 将复位信号延迟一个时钟周期，确保复位信号能够正确地异步置位PC寄存器
    always_ff @(posedge clk) begin
        rst_delay <= rst;
    end
*/

    // PC寄存器的主要逻辑：使用异步复位
    // 当rst或rst_delay为高电平时，PC被设置为复位值
    // 否则，在每个时钟上升沿将npc的值加载到PC寄存器中
    always_ff @(posedge clk, posedge rst) begin
        if (rst /*| rst_delay*/) 
            reg_pc <= RESET_VAL;  // 复位时设置为初始值
        else 
            reg_pc <= npc;                         // 正常工作时更新为下一个PC值
    end 

    // 将内部PC寄存器的值赋给输出端口
    assign pc_out = reg_pc;
endmodule
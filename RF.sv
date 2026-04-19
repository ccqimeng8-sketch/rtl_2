`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: RF
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 寄存器堆（Register File）模块
//              实现32个通用寄存器的读写功能
//              支持双端口读和单端口写
//              x0寄存器（地址0）硬连线为0，不可写入
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module RF #(
    parameter   ADDR_WIDTH = 5  ,  // 寄存器地址宽度，5位可寻址32个寄存器
    parameter   DATAWIDTH  = 32    // 数据宽度，默认为32位
)(
    input  logic                    clk            ,  // 时钟信号
    input  logic                    rst            ,  // 复位信号，高电平有效
    // 写端口：写rd寄存器                   
    input  logic                    wen      ,       // 写使能信号
    input  logic [ADDR_WIDTH - 1:0] waddr    ,       // 写地址（目标寄存器rd）
    input  logic [DATAWIDTH - 1:0]  wdata       ,    // 写数据
    // 读端口1：读rs1寄存器
    input  logic [ADDR_WIDTH - 1:0] rR1   ,          // 读地址1（源寄存器rs1）
    // 读端口2：读rs2寄存器
    input  logic [ADDR_WIDTH - 1:0] rR2   ,          // 读地址2（源寄存器rs2）

    output logic [DATAWIDTH - 1:0]  rR1_data  ,      // 读数据1（rs1的值）
    output logic [DATAWIDTH - 1:0]  rR2_data         // 读数据2（rs2的值）
);
    logic [DATAWIDTH - 1:0] reg_bank [31:0] = '{default:0};  // 初始化所有寄存器为0

    // 寄存器写操作：同步时序逻辑
    // 复位时将所有寄存器清零
    // 正常工作时，当写使能有效且写地址不为0时，将数据写入指定寄存器
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            // 复位：将所有32个寄存器初始化为0
            for (int i = 0; i < 32; i ++) begin
                reg_bank[i] <= 0;
            end
        end
        else if (wen & (waddr != 5'd0)) begin
            // 写操作：x0寄存器（地址0）始终保持为0，不允许写入
            reg_bank[waddr] <= wdata;
        end
    end

    //

    // 修改为纯组合逻辑读，x0硬连线为0
    assign rR1_data = (rR1 == 5'd0) ? 32'b0 : reg_bank[rR1];
    assign rR2_data = (rR2 == 5'd0) ? 32'b0 : reg_bank[rR2];

endmodule

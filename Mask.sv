`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: Mask
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 数据掩码模块（Mask Unit）
//              对加载指令的数据进行符号扩展和位掩码处理
//              支持字节（lb）、半字（lh）、字（lw）加载
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module Mask#(
    parameter   DATAWIDTH = 32	  // 数据宽度，默认为32位
)(
    input  logic [2:0]             mask   ,  // 掩码控制信号（3位）
    input  logic [DATAWIDTH - 1:0] dout	  ,  // 从存储器读出的原始数据
	output logic [DATAWIDTH - 1:0] mdata     // 处理后的数据（符号扩展或原样输出）
);
    // 加载类型解码信号
    logic op_other, op_lb, op_lh;

    // 根据mask字段判断加载类型
    assign op_lb = mask == `MASK_LB;   // lb/lbu: 字节加载
    assign op_lh = mask == `MASK_LH;   // lh/lhu: 半字加载
    assign op_other = ~(op_lh | op_lb);  // 其他：字加载（lw）

    // 数据处理：根据加载类型进行符号扩展
    // lb: 取低8位，符号扩展到32位
    // lh: 取低16位，符号扩展到32位
    // lw: 保持原样（32位）
    assign mdata = {32{op_lb}} & {{25{dout[7]}}, dout[6:0]} |
                {32{op_lh}} & {{17{dout[15]}}, dout[14:0]} |
                {32{op_other}} & dout;

endmodule
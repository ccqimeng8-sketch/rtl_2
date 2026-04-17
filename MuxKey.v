`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: MuxKey
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 键控多路选择器模块（Keyed Multiplexer）
//              根据键值从查找表中选择对应的数据输出
//              用于实现灵活的多路选择功能
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module MuxKey #(NR_KEY = 2, KEY_LEN = 1, DATA_LEN = 1) (
  output [DATA_LEN-1:0] out,   // 输出数据
  input [KEY_LEN-1:0] key,     // 键值输入
  input [NR_KEY*(KEY_LEN + DATA_LEN)-1:0] lut  // 查找表输入（包含键值和数据对）
);
  // 实例化内部模块，无默认值
  MuxKeyInternal #(NR_KEY, KEY_LEN, DATA_LEN, 0) i0 (out, key, {DATA_LEN{1'b0}}, lut);
endmodule
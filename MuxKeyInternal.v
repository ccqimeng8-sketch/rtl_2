`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: MuxKeyInternal
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 键控多路选择器内部实现模块
//              实现基于键值匹配的查找表多路选择器
//              支持可选的默认输出值
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module MuxKeyInternal #(NR_KEY = 2, KEY_LEN = 1, DATA_LEN = 1, HAS_DEFAULT = 0) (
  output reg [DATA_LEN-1:0] out,   // 输出数据
  input [KEY_LEN-1:0] key,         // 键值输入
  input [DATA_LEN-1:0] default_out, // 默认输出（当HAS_DEFAULT=1时使用）
  input [NR_KEY*(KEY_LEN + DATA_LEN)-1:0] lut  // 查找表输入
);

  // 参数定义：每对键值-数据的总长度
  localparam PAIR_LEN = KEY_LEN + DATA_LEN;
  
  // 查找表解析：将线性lut数组解析为键值和数据列表
  wire [PAIR_LEN-1:0] pair_list [NR_KEY-1:0];  // 键值-数据对列表
  wire [KEY_LEN-1:0] key_list [NR_KEY-1:0];    // 键值列表
  wire [DATA_LEN-1:0] data_list [NR_KEY-1:0];  // 数据列表

  genvar n;
  generate
    // 生成块：将lut分解为独立的键值和数据
    for (n = 0; n < NR_KEY; n = n + 1) begin
      assign pair_list[n] = lut[PAIR_LEN*(n+1)-1 : PAIR_LEN*n];  // 提取第n对
      assign data_list[n] = pair_list[n][DATA_LEN-1:0];          // 提取数据部分
      assign key_list[n]  = pair_list[n][PAIR_LEN-1:DATA_LEN];   // 提取键值部分
    end
  endgenerate

  // 组合逻辑：键值匹配和数据选择
  reg [DATA_LEN-1 : 0] lut_out;  // 查找表输出
  reg hit;                       // 命中标志
  integer i;
  
  always @(*) begin
    lut_out = 0;  // 初始化输出
    hit = 0;      // 初始化命中标志
    
    // 遍历所有键值对，查找匹配项
    for (i = 0; i < NR_KEY; i = i + 1) begin
      // 如果键值匹配，则将对应数据输出
      lut_out = lut_out | ({DATA_LEN{key == key_list[i]}} & data_list[i]);
      // 更新命中标志
      hit = hit | (key == key_list[i]);
    end
    
    // 根据是否有默认值决定输出
    if (!HAS_DEFAULT) out = lut_out;  // 无默认值：直接输出查找结果
    else out = (hit ? lut_out : default_out);  // 有默认值：未命中时输出默认值
  end
endmodule
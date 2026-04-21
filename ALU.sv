`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/01 10:31:41
// Design Name: 
// Module Name: ALU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 算术逻辑单元（Arithmetic Logic Unit）模块
//              执行各种算术和逻辑运算
//              支持加法、减法、位运算、移位、比较等操作
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ALU#(
    parameter   DATAWIDTH = 32	  // 数据宽度，默认为32位
)(
    input  logic                    valid       ,  // 流水线有效信号（新增）
    input  logic [DATAWIDTH - 1:0]  A           ,  // 操作数A
    input  logic [DATAWIDTH - 1:0]  B           ,  // 操作数B
    input  logic [13:0]             ALUControl  ,  // ALU控制信号（14位独热码）
    output logic [DATAWIDTH - 1:0]  Result      ,  // 运算结果
    output logic                    isTrue         // 分支条件判断结果
);

    // ALU操作使能信号，从ALUControl中解码
    logic op_add, op_sub, op_and, op_or, op_xor, op_sll, op_srl;
    logic op_sra, op_beq, op_bne, op_blt, op_bge, op_bgeu, op_bltu;

    // 将14位ALUControl信号分解为独立的操作使能信号
    assign op_add = ALUControl[0];
    assign op_sub = ALUControl[1];
    assign op_and = ALUControl[2];
    assign op_or = ALUControl[3];
    assign op_xor = ALUControl[4];
    assign op_sll = ALUControl[5];
    assign op_srl = ALUControl[6];
    assign op_sra = ALUControl[7];
    assign op_beq = ALUControl[8];
    assign op_bne = ALUControl[9];
    assign op_blt = ALUControl[10];
    assign op_bge = ALUControl[11];
    assign op_bgeu = ALUControl[12];
    assign op_bltu = ALUControl[13];

    // 各类运算的中间结果信号
    logic [DATAWIDTH-1:0] add_sub_result, and_result, or_result, xor_result;
    logic [DATAWIDTH-1:0] sll_result, srl_result, sra_result, beq_result, bne_result;
    logic [DATAWIDTH-1:0] blt_result, bge_result, bgeu_result, bltu_result;

    // 加法器输入信号
    logic [DATAWIDTH-1:0] adder_a, adder_b;
    logic cin, carry;

    // 加法器输入准备：使用补码实现减法
    assign adder_a = A;
    // 对于减法或比较操作，对B取反并设置进位为1（实现A-B = A+~B+1）
    assign adder_b = (op_sub | op_blt | op_bge | op_bgeu | op_bltu) ? ~B : B;
    assign cin = (op_sub | op_blt | op_bge | op_bgeu | op_bltu) ? 1'b1 : 0;

    /* verilator lint_off WIDTHEXPAND */
    // 加法/减法运算：通过进位扩展检测溢出
    assign {carry, add_sub_result} = adder_a + adder_b + cin;

    // 位运算操作
    assign and_result = A & B;       // 按位与
    assign or_result = A | B;        // 按位或
    assign xor_result = A ^ B;       // 按位异或
    
    // 移位操作：只使用B的低5位作为移位量（0-31）
    assign sll_result = A << B[4:0];                    // 逻辑左移
    assign srl_result = A >> B[4:0];                    // 逻辑右移
    assign sra_result = ($signed(A)) >>> B[4:0];       // 算术右移（保持符号位）
    
    // 比较操作结果：返回1位布尔值扩展为32位
    assign beq_result = {31'b0, A == B};                                    // 相等比较
    assign bne_result = {31'b0, A != B};                                    // 不等比较
    // 有符号小于：检查符号位不同时的情况，或符号位相同时减法结果的符号
    assign blt_result = {31'b0, (A[31] &  ~B[31]) | ((~A[31] ^ B[31]) & add_sub_result[31])};
    assign bge_result = ~blt_result;                                        // 有符号大于等于（取反）
    assign bgeu_result = {31'b0, carry};                                   // 无符号大于等于（检查进位）
    assign bltu_result = {31'b0, ~carry};                                  // 无符号小于（进位取反）

    // isTrue输出Result[0]
    assign isTrue = Result[0];

    // 最终结果选择：使用独热码多路选择器
    // 根据ALUControl信号选择对应的运算结果
    assign Result = {32{op_add | op_sub}} & add_sub_result |
                    {32{op_and}} & and_result |
                    {32{op_or}} & or_result |
                    {32{op_xor}} & xor_result |
                    {32{op_sll}} & sll_result |
                    {32{op_srl}} & srl_result |
                    {32{op_sra}} & sra_result |
                    {32{op_beq}} & beq_result |
                    {32{op_bne}} & bne_result |
                    {32{op_blt}} & blt_result |
                    {32{op_bge}} & bge_result |
                    {32{op_bgeu}} & bgeu_result |
                    {32{op_bltu}} & bltu_result;

endmodule
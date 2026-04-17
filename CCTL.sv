`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: CCTL
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: CSR控制单元（CSR Control Unit）模块
//              从指令中解码CSR相关操作
//              支持csrrs、csrrw、ecall、mret等CSR指令
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module CCTL (
	input  logic [31:0] instr		,  // 指令字（32位）
	output logic [11:0] csr_idx		,  // CSR寄存器索引（12位）
	output logic [3:0]  CSRControll    // CSR控制信号（4位）
);
	// 从指令的[31:20]位提取CSR寄存器索引
	assign csr_idx = instr[31:20];
	
	// CSR控制信号解码
	assign CSRControll[0] = (instr[6:0] == 7'b1110011) && (instr[14:12] == 3'b010); // csrrs: CSR读并置位
	assign CSRControll[1] = (instr[6:0] == 7'b1110011) && (instr[14:12] == 3'b001); // csrrw: CSR读并写入
	assign CSRControll[2] = instr == 32'h00000073; // ecall: 环境调用（系统调用）
	assign CSRControll[3] = instr == 32'h30200073; // mret: 机器模式返回
endmodule
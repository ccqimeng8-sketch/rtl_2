`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: CSR
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 控制和状态寄存器（Control and Status Register）模块
//              实现RISC-V机器模式的CSR寄存器
//              支持mstatus、mepc、mtvec、mcause等关键CSR
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module CSR #(
    parameter   DATAWIDTH = 32	  // 数据宽度，默认为32位
)(
	input  logic 					clk			,  // 时钟信号
	input  logic 					rst			,  // 复位信号
	input  logic [DATAWIDTH-1:0]	pc			,  // 当前PC值
	input  logic [DATAWIDTH-1:0]	rf1			,  // 寄存器堆读出的数据（用于CSR写入）
	input  logic [11:0] 			csr_idx		,  // CSR寄存器索引
	input  logic [3:0]  			CSRControll	,  // CSR控制信号

	output logic [DATAWIDTH-1:0] 	csr_npc		,  // CSR计算的下一个PC地址（用于异常/中断）
	output logic [DATAWIDTH-1:0]	csr_wb          // CSR写回数据（用于csrrs/csrrw指令）
);
	// CSR寄存器定义
	reg [DATAWIDTH-1:0] mstatus, mepc, mtvec, mcause;  // 当前CSR值
	reg [DATAWIDTH-1:0] old_mstatus, old_mepc, old_mtvec, old_mcause;  // 旧值备份（用于读取）
	reg [DATAWIDTH-1:0] mask;  // 掩码寄存器

	// 信号初始化：复位时设置mask为全1
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			mask <= 32'hFFFFFFFF;
		end
	end

	// 寄存器备份：保存CSR的旧值，用于读取操作
	// mstatus旧值备份
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			old_mstatus <= 32'h0;
		end else begin
			old_mstatus <= mstatus;  // 每个时钟周期更新旧值
		end
	end

	// mepc旧值备份
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			old_mepc <= 32'h0;
		end else begin
			old_mepc <= mepc;
		end
	end

	// mtvec旧值备份
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			old_mtvec <= 32'h0;
		end else begin
			old_mtvec <= mtvec;
		end
	end

	// mcause旧值备份
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			old_mcause <= 32'h0;
		end else begin
			old_mcause <= mcause;
		end
	end

	// mstatus寄存器更新逻辑
	// mstatus包含全局中断使能、特权模式等状态信息
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			mstatus <= 32'h1800;  // 复位值：MPP=11（机器模式）
		end else begin
			case (CSRControll)
				// csrrs: 读并置位，将rf1中的1位设置到mstatus
				`CSR_CTRL_RS: if (csr_idx == `CSR_MSTATUS) mstatus <= mask & (old_mstatus | rf1);
				// csrrw: 读并写入，直接将rf1写入mstatus
				`CSR_CTRL_RW: if (csr_idx == `CSR_MSTATUS) mstatus <= mask & rf1;
				// ecall: 保存当前MPP和MPIE，清除MIE
				`CSR_CTRL_ECALL: mstatus <= { old_mstatus[31:8], old_mstatus[3], old_mstatus[6:4], old_mstatus[2:0] };
				// mret: 恢复MPP和MPIE，设置MIE
				`CSR_CTRL_MRET: mstatus <= { old_mstatus[31:13], 2'b11, old_mstatus[10:8], 1'b1, old_mstatus[6:4], old_mstatus[3], old_mstatus[2:0] };
				default: mstatus <= mstatus; // 保持原值
			endcase
		end
	end

	// mtvec寄存器更新逻辑
	// mtvec存储陷阱向量基地址，异常/中断时跳转到此地址
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			mtvec <= 32'h0;
		end else begin
			case (CSRControll)
				// csrrs: 读并置位
				`CSR_CTRL_RS: if (csr_idx == `CSR_MTVEC) mtvec <= old_mtvec | rf1;
				// csrrw: 读并写入
				`CSR_CTRL_RW: if (csr_idx == `CSR_MTVEC) mtvec <= rf1;
				default: mtvec <= mtvec;  // 保持原值
			endcase
		end
	end

	// mepc寄存器更新逻辑
	// mepc存储异常/中断发生时的PC值，mret时返回此地址
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			mepc <= 32'h0;
		end else begin
			case (CSRControll)
				// csrrs: 读并置位
				`CSR_CTRL_RS: if (csr_idx == `CSR_MEPC) mepc <= old_mepc | rf1;
				// csrrw: 读并写入
				`CSR_CTRL_RW: if (csr_idx == `CSR_MEPC) mepc <= rf1;
				// ecall: 保存当前PC到mepc
				`CSR_CTRL_ECALL: mepc <= pc;
				default: mepc <= mepc;  // 保持原值
			endcase
		end
	end

	// mcause寄存器更新逻辑
	// mcause存储异常/中断的原因代码
	always @(posedge clk or posedge rst) begin
		if (rst) begin
			mcause <= 32'h0;
		end else begin
			case (CSRControll)
				// csrrs: 读并置位
				`CSR_CTRL_RS: if (csr_idx == `CSR_MCAUSE) mcause <= old_mcause | rf1;
				// csrrw: 读并写入
				`CSR_CTRL_RW: if (csr_idx == `CSR_MCAUSE) mcause <= rf1;
				// ecall: 设置异常原因为11（环境调用）
				`CSR_CTRL_ECALL: mcause <= 32'h0b;  // environment call from M-mode
				default: mcause <= mcause;  // 保持原值
			endcase
		end
	end

	// CSR写回数据选择：根据csr_idx选择对应的CSR旧值输出
	// 用于csrrs/csrrw指令将CSR的旧值写回寄存器堆
	assign csr_wb = {32{csr_idx == `CSR_MSTATUS}} & old_mstatus |
				{32{csr_idx == `CSR_MTVEC}} & old_mtvec |
				{32{csr_idx == `CSR_MEPC}} & old_mepc |
				{32{csr_idx == `CSR_MCAUSE}} & old_mcause;

	// CSR计算的下一个PC地址：用于异常处理和mret指令
	// ecall时跳转到mtvec，mret时返回mepc
	assign csr_npc =  {32{CSRControll == `CSR_CTRL_ECALL}} & old_mtvec |  // ecall: 跳转到陷阱向量
				{32{CSRControll == `CSR_CTRL_MRET}} & old_mepc;          // mret: 返回异常前的PC
	
	
endmodule
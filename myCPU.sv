`timescale 1ns / 1ps
`include "defines.sv"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/24 10:51:04
// Design Name: 
// Module Name: myCPU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: RISC-VCPU顶层模块
//              集成所有子模块实现完整的CPU功能
//              支持RV32I基本整数指令集
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module myCPU (
    input  logic         cpu_rst,   // CPU复位信号
    input  logic         cpu_clk,   // CPU时钟信号

    // IROM接口：指令存储器
    output logic [31:0]  irom_addr, // 指令地址
    input  logic [31:0]  irom_data, // 指令数据
    
    // DRAM接口：数据/外设存储器
    output logic [31:0]  perip_addr,  // 外设地址
    output logic         perip_wen,   // 外设写使能
	output logic [ 1:0]  perip_mask,  // 外设字节掩码
    output logic [31:0]  perip_wdata, // 外设写数据
    input  logic [31:0]  perip_rdata  // 外设读数据
);

    parameter	DATAWIDTH  = 32             ;
  	parameter   RESET_VAL  = 32'h8000_0000  ;
	parameter   ADDR_WIDTH = 5				;

	logic 					clk, rst		;
    logic [DATAWIDTH-1:0] 	offset          ;
    logic [1:0]				NpcOp	        ;
    logic [2:0]				MemToReg        ;
    logic 					RegWrite        ;
	logic [1:0]  			OffsetOrigin    ;
	logic [DATAWIDTH-1:0]	imm		        ;
	//logic [DATAWIDTH-1:0]	csr_npc	        ;
	logic 					isTrue	        ;
    logic [6:0]				opcode	        ;
    logic [3:0]				funct	        ;
    logic [DATAWIDTH-1:0]	A		        ;
    logic [DATAWIDTH-1:0]	B		        ;
    //logic [11:0]			csr_idx	        ;
    //logic [3:0]			CSRControll     ;    
    logic  					ALUSrcA, ALUSrcB;
	logic [DATAWIDTH-1:0]	ALU_A, ALU_B	;
    logic [13:0] ALUControl;
    logic [DATAWIDTH-1:0]	mdata 			;

	logic [DATAWIDTH-1:0] 	npc		        ;
	logic [DATAWIDTH-1:0] 	instr	        ;
	logic [DATAWIDTH-1:0] 	pcadd4          ;
    logic [DATAWIDTH-1:0]	wdata           ;
    logic [DATAWIDTH-1:0]	daddr           ;

	logic [31:0]  			Result			;
    logic         			MemWrite		;
    logic [31:0]  			rR2_data		;
    logic [31:0]  			data_out		;

	logic [DATAWIDTH-1:0]	pc				;

	// 流水线寄存器临时信号声明
	logic [DATAWIDTH-1:0]	pcadd4_temp, 	pcadd4_temp1, 	pcadd4_temp2, 	pcadd4_temp3, pcadd4_temp4;
	logic [DATAWIDTH-1:0]	pc_temp, 		pc_temp1, 		pc_temp2;
	logic [DATAWIDTH-1:0]	instr_temp, 	instr_temp1, 	instr_temp2, instr_temp3;
	logic [6:0]				opcode_temp, 	opcode_temp1;
	logic [3:0]				funct_temp, 	funct_temp1;
	logic 					RegWrite_temp, 	RegWrite_temp1, RegWrite_temp2;
	logic [2:0]				MemToReg_temp, 	MemToReg_temp1, MemToReg_temp2;
	logic 					MemWrite_temp;
	logic 					ALUSrcA_temp, 	ALUSrcB_temp;
	logic [DATAWIDTH-1:0]	imm_temp, 		imm_temp1, 		imm_temp2;
	logic [DATAWIDTH-1:0]	daddr_temp, daddr_temp1;
	//logic [DATAWIDTH-1:0]	csr_wb_temp,	csr_wb_temp1;
	logic [DATAWIDTH-1:0]	mdata_temp; 
	
	// valid 信号声明
	logic valid_temp, valid_temp1, valid_temp2, valid_temp3;

	// 前推信号声明
	logic [DATAWIDTH-1:0]	ALU_A_fwd, ALU_B_fwd;
	logic [DATAWIDTH-1:0]	ALU_B_fwd_temp;

	// IROM接口连接：PC输出到指令存储器，读取指令
	assign irom_addr = pc;
	assign instr = irom_data;  // 修正：instr 才是后续使用的信号
	assign clk 			= cpu_clk;             	// 时钟信号传递
    assign rst 			= cpu_rst;             	// 复位信号传递

	// ==================== 模块实例化 ====================
	
	// PC模块：程序计数器
	PC #(DATAWIDTH, RESET_VAL) pc_inst (
		.clk  	(clk)	    , // Input: 时钟信号
		.rst	(rst)	    , // Input: 复位信号
		.npc  	(npc)	    , // Input: 下一个PC值
		.pc_out	(pc)          // Output: 当前PC值输出
	);

	// NPC模块：下一程序计数器计算
	NPC #(DATAWIDTH) npc_inst (
		.isTrue   (isTrue)	, // Input: 分支条件判断结果
		.npc_op   (NpcOp)	, // Input: NPC操作选择
		.pc       (pc)		, // Input: 当前PC值
		.offset   (offset)	, // Input: 偏移量
		.npc      (npc)		, // Output: 下一条指令地址
		.pcadd4	  (pcadd4)    // Output: PC+4的结果 (连接到中间信号)
	);

	// 偏移量选择：根据OffsetOrigin选择offset的来源
    // 00: 立即数，01: ALU结果，10: CSR计算的NPC
    always_comb begin
    if (!valid_temp)
        offset = 32'b0;
    else begin
        case (OffsetOrigin)
            2'b00: offset = imm_temp;
            2'b01: offset = daddr;
            default: offset = 32'b0;
        endcase
    	end
	end

	// IF/ID 流水线寄存器 (dff_1)
	dff_1 dff1_inst(
		.clk          (clk),
		.rst          (rst),
		.in_pc_add4   (pcadd4),
		.out_pc_add4  (pcadd4_temp),     
		.in_pc        (pc),
		.out_pc       (pc_temp),  
		.in_instr     (instr),
		.out_instr    (instr_temp),
		.in_valid     (~rst), // 初始 valid = not reset
		.out_valid    (valid_temp)       
	);

	// 指令字段提取
	assign opcode = instr_temp[6:0];           // 提取opcode
	assign funct = {instr_temp[30], instr_temp[14:12]};  // 提取funct
	
	// Control模块：控制单元
	Control control_inst (
		.opcode      	(opcode)		, // Input: 指令操作码
		.funct			(funct[2:0])	, // Input: 指令功能码
		.NpcOp       	(NpcOp)			, // Output: NPC操作选择
		.RegWrite    	(RegWrite)		, // Output: 寄存器写使能
		.MemToReg    	(MemToReg)		, // Output: 写回数据源选择
		.MemWrite    	(MemWrite)		, // Output: 存储器写使能
		.OffsetOrigin	(OffsetOrigin)	, // Output: 偏移量来源选择
		.ALUSrcA      	(ALUSrcA)		, // Output: ALU操作数A来源选择
		.ALUSrcB      	(ALUSrcB)       // Output: ALU操作数B来源选择
	);

	// IMMGEN模块：立即数生成器
	IMMGEN #(DATAWIDTH) immgen_inst (
		.instr   (instr_temp), // Input: 指令字
		.imm     (imm)    // Output: 生成的立即数
	);
	
		// RF模块：寄存器文件
	RF #(ADDR_WIDTH, DATAWIDTH) rf_inst (
		.clk        (clk),          // Input: 时钟信号
		.rst        (rst),          // Input: 复位信号
		.wen      	(RegWrite_temp2 & valid_temp3),     // Input: 写使能（增加valid判断）
		.waddr    	(instr_temp3[11:7]),  // Input: 写地址（rd）
		.wdata      (wdata),         // Input: 写数据
		.rR1   		(instr_temp1[19:15]), // Input: 读地址1（rs1）
		.rR2   		(instr_temp1[24:20]), // Input: 读地址2（rs2）
		.rR1_data  	(ALU_A),        // Output: 读数据1
		.rR2_data	(ALU_B)         // Output: 读数据2
	);

	dff_2 dff_2_inst (
		.clk      		(clk),         // Input: 时钟
		.rst      		(rst),         // Input: 复位
		.in_pc_add4 	(pcadd4_temp),      // Input: 来自 dff_1 的 PC+4
		.out_pc_add4 	(pcadd4_temp1),            // Output: 传递给下一级的 PC+4 (若后续模块需要可连接对应信号)	
		.in_pc      	(pc_temp),          // Input: 当前 PC
		.out_pc     	(pc_temp1),            // Output: 传递给下一级的 PC
		.in_opcode  	(opcode),      // Input: 指令操作码
		.out_opcode 	(opcode_temp),            // Output: 传递给下一级的 opcode
		.in_funct   	(funct),       // Input: 指令功能码
		.out_funct  	(funct_temp),            // Output: 传递给下一级的 funct
		.in_NpcOp   	(NpcOp),       // Input: NPC操作选择
		.out_NpcOp  	(NpcOp_temp),            // Output: 传递给下一级的 NpcOp
		.in_RegWrite	(RegWrite),    // Input: 寄存器写使能
		.out_RegWrite	(RegWrite_temp),            // Output: 传递给下一级的 RegWrite
		.in_MemToReg	(MemToReg),    // Input: 写回数据源选择
		.out_MemToReg	(MemToReg_temp),            // Output: 传递给下一级的 MemToReg
		.in_MemWrite	(MemWrite),    // Input: 存储器写使能
		.out_MemWrite	(MemWrite_temp),            // Output: 传递给下一级的 MemWrite
		.in_OffsetOrigin(OffsetOrigin),// Input: 偏移量来源选择
		.out_OffsetOrigin(OffsetOrigin_temp),           // Output: 传递给下一级的 OffsetOrigin
		.in_ALUSrcA 	(ALUSrcA),     // Input: ALU操作数A来源选择
		.out_ALUSrcA	(ALUSrcA_temp),            // Output: 传递给下一级的 ALUSrcA
		.in_ALUSrcB 	(ALUSrcB),     // Input: ALU操作数B来源选择
		.out_ALUSrcB	(ALUSrcB_temp),            // Output: 传递给下一级的 ALUSrcB
		.in_imm     	(imm),         // Input: 生成的立即数
		.out_imm    	(imm_temp),             // Output: 传递给下一级的 imm
		.in_instr     	(instr_temp),	// Input: 输入的指令
		.out_instr    	(instr_temp1),             // Output: 输出的指令
		.in_valid       (valid_temp),
		.out_valid      (valid_temp1)
	);
	
	// ==================== 数据前推逻辑 (Forwarding Unit) ====================
	
	// 实例化 Forwarding Unit
	FU fu_inst (
		// ID/EX 阶段信号
		.rs1_ex         (instr_temp1[19:15]),
		.rs2_ex         (instr_temp1[24:20]),
		.reg_data_A     (ALU_A), // 注意：这里使用 dff_2 输出的 ALU_A/B，即寄存器堆读出的原始值
		.reg_data_B     (ALU_B),
		.valid_ex       (valid_temp1),

		// EX/MEM 阶段信号 (来自 dff_3 输出/当前 EX 阶段计算结果)
		.rd_ex          (instr_temp2[11:7]),
		.reg_write_ex   (RegWrite_temp1),
		.mem_to_reg_ex  (MemToReg_temp1),
		.alu_result_ex  (daddr),      // 当前 ALU 结果
		.valid_mem      (valid_temp2), // 新增：EX/MEM阶段有效信号

		// MEM/WB 阶段信号 (来自 dff_4 输出)
		.rd_mem         (instr_temp3[11:7]),
		.reg_write_mem  (RegWrite_temp2),
		.mem_to_reg_mem (MemToReg_temp2),
		.alu_result_mem (daddr_temp),
		.mem_data_mem   (mdata_temp),
		.valid_wb       (valid_temp3), // 新增：MEM/WB阶段有效信号

		// 输出
		.fwd_alu_a      (ALU_A_fwd),
		.fwd_alu_b      (ALU_B_fwd)
	);

	// ALU操作数选择 (使用前推后的数据)
	// 注意：ALUSrcA/B 选择的是前推后的数据还是立即数/PC
	assign B = ALUSrcB_temp ? imm_temp : ALU_B_fwd;  
	assign A = ALUSrcA_temp ? pc_temp1 : ALU_A_fwd;   

    // ALU模块：算术逻辑单元
    ALU #(DATAWIDTH) alu_inst (
		.valid       (valid_temp1), // Input: 流水线有效信号（新增连接）
		.A           (A),           // Input: 操作数A
		.B           (B),           // Input: 操作数B
		.ALUControl  (ALUControl),  // Input: ALU控制信号
		.Result      (daddr),       // Output: 运算结果
		.isTrue      (isTrue)       // Output: 分支条件判断结果
	);

	// ACTL模块：ALU控制单元
	ACTL actl_inst (
		.opcode       (opcode_temp),     // Input: 指令操作码
		.funct        (funct_temp),      // Input: 指令功能码
		.ALUControl   (ALUControl)  // Output: ALU控制信号
	);
/*
	// CSR模块：控制和状态寄存器
	CSR #(DATAWIDTH) csr_inst (
		.clk			(clk),          // Input: 时钟信号
		.rst			(rst),          // Input: 复位信号
		.pc				(pc_temp2),           // Input: 当前PC值
		.rf1			(A_temp),            // Input: ALU操作数1的值
		.csr_idx		(csr_idx),      // Input: CSR寄存器索引
		.CSRControll	(CSRControll),  // Input: CSR控制信号
		.csr_npc		(csr_npc),      // Output: CSR计算的下一个PC地址
		.csr_wb			(csr_wb)        // Output: CSR写回数据
	);
	
	// CCTL模块：CSR控制单元
	CCTL cctl_inst (
		.instr		 	(instr_temp2),      // Input: 指令字
		.csr_idx		(csr_idx),    // Output: CSR寄存器索引
		.CSRControll  	(CSRControll) // Output: CSR控制信号
	);
	*/
	//dff_mem
	dff_3 dff_3_inst (
		.clk            (clk),
		.rst            (rst),
		.in_instr       (instr_temp1),
		.out_instr      (instr_temp2),
		.in_funct       (funct_temp),
		.out_funct      (funct_temp1),
		.in_MemToReg    (MemToReg_temp),
		.out_MemToReg   (MemToReg_temp1),
		.in_pc_add4     (pcadd4_temp1),
		.out_pc_add4    (pcadd4_temp2),
		.in_daddr       (daddr),
		.out_daddr      (daddr_temp),
		.in_imm         (imm_temp),
		.out_imm        (imm_temp1),
		.in_RegWrite    (RegWrite_temp), 
		.out_RegWrite   (RegWrite_temp1),
		.in_MemWrite    (MemWrite_temp),
		.out_MemWrite   (MemWrite_temp1),
		.in_ALU_B   	(ALU_B_fwd),
		.out_ALU_B   	(ALU_B_fwd_temp),
		.in_valid       (valid_temp1),
		.out_valid      (valid_temp2)
		//.in_csr_wb      (csr_wb),
		//.out_csr_wb     (csr_wb_temp),
	);

	// Mask模块：数据掩码处理
	Mask #(DATAWIDTH) mask_inst (
		.mask   	(funct_temp1[2:0]), // Input: 掩码控制信号
		.dout	  	(perip_rdata),       // Input: 从存储器读出的原始数据
		.mdata		(mdata)       // Output: 处理后的数据 (修改为来自 dff_4 的输出)
	);

	//MEM_Access stage
	assign perip_addr = daddr_temp;
    assign perip_wen  = MemWrite_temp1 & valid_temp2;  // 增加valid判断（注意：MemWrite_temp1来自dff_3，对应valid_temp2）
    assign perip_mask = funct_temp1[1:0];  
    assign perip_wdata = ALU_B_fwd_temp;

	dff_4 dff_4_inst (
		.clk            (clk),
		.rst            (rst),
		.in_instr       (instr_temp2),
		.out_instr      (instr_temp3),
		.in_MemToReg    (MemToReg_temp1),
		.out_MemToReg   (MemToReg_temp2),
		.in_pc_add4     (pcadd4_temp2),
		.out_pc_add4    (pcadd4_temp3),
		.in_daddr       (daddr_temp),
		.out_daddr      (daddr_temp1),
		.in_imm         (imm_temp1),
		.out_imm        (imm_temp2),
		.in_RegWrite    (RegWrite_temp1),
		.out_RegWrite   (RegWrite_temp2),
		.in_mdata       (mdata),          
		.out_mdata      (mdata_temp),
		.in_valid       (valid_temp2),
		.out_valid      (valid_temp3)
		//.in_csr_wb      (csr_wb_temp),
		//.out_csr_wb     (csr_wb_temp1)    
	);
	
	// MuxKey模块：写回数据多路选择器
	// 根据MemToReg选择写回寄存器的数据来源：
	// 000: pcadd4, 001: daddr(ALU结果), 010: mdata(存储器数据), 011: imm(立即数), 100: csr_wb(CSR数据)
	MuxKey #(5, 3, DATAWIDTH) mux_alu (
        .out    (wdata),        // Output: 选中的数据输出到寄存器堆写端口
        .key    (MemToReg_temp2),     // Input: 选择键值
        .lut    ({              // Input: 查找表数据
		    `MEM_TO_REG_PCADD4, pcadd4_temp3,
		    `MEM_TO_REG_ALU   , daddr_temp1	,
		    `MEM_TO_REG_MEM   , mdata_temp,
		    `MEM_TO_REG_IMM   , imm_temp2,
		    `MEM_TO_REG_CSR   , 32'b0
	    })
    );
endmodule
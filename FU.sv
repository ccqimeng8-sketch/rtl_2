`timescale 1ns / 1ps
`include "defines.sv"

module FU (
    // ID/EX 阶段信号 (当前指令)
    input  logic [4:0]  rs1_ex,         // 当前指令的 rs1
    input  logic [4:0]  rs2_ex,         // 当前指令的 rs2
    input  logic [31:0] reg_data_A,     // 从寄存器堆读出的 rs1 数据 (ALU_A_temp)
    input  logic [31:0] reg_data_B,     // 从寄存器堆读出的 rs2 数据 (ALU_B_temp)
    input  logic        valid_ex,       // 新增：ID/EX阶段指令有效信号

    // EX/MEM 阶段信号 (上一条指令)
    input  logic [4:0]  rd_ex,          // 上一条指令的目标寄存器 rd
    input  logic        reg_write_ex,   // 上一条指令的 RegWrite
    input  logic [2:0]  mem_to_reg_ex,  // 上一条指令的 MemToReg
    input  logic [31:0] alu_result_ex,  // 上一条指令的 ALU 结果 (daddr)
    input  logic        valid_mem,      // 新增：EX/MEM阶段指令有效信号

    // MEM/WB 阶段信号 (上上条指令)
    input  logic [4:0]  rd_mem,         // 上上条指令的目标寄存器 rd
    input  logic        reg_write_mem,  // 上上条指令的 RegWrite
    input  logic [2:0]  mem_to_reg_mem, // 上上条指令的 MemToReg
    input  logic [31:0] alu_result_mem, // 上上条指令的 ALU 结果 (daddr_temp)
    input  logic [31:0] mem_data_mem,   // 上上条指令的内存数据 (mdata)
    input  logic        valid_wb,       // 新增：MEM/WB阶段指令有效信号

    // 输出：前推后的操作数
    output logic [31:0] fwd_alu_a,
    output logic [31:0] fwd_alu_b
);

    logic fwd_a_ex, fwd_a_mem;
    logic fwd_b_ex, fwd_b_mem;
    logic [31:0] fwd_data_a, fwd_data_b;

    // --- 前推控制信号生成 ---
    
    // 前推 A (rs1)
    assign fwd_a_ex  = valid_mem && (rs1_ex != 0) && (rd_ex != 0) && (rs1_ex == rd_ex)  && reg_write_ex;
    assign fwd_a_mem = valid_wb  && (rs1_ex != 0) && (rd_mem != 0) && (rs1_ex == rd_mem) && reg_write_mem;

    // 前推 B (rs2)
    assign fwd_b_ex  = valid_mem && (rs2_ex != 0) && (rd_ex != 0) && (rs2_ex == rd_ex)  && reg_write_ex;
    assign fwd_b_mem = valid_wb  && (rs2_ex != 0) && (rd_mem != 0) && (rs2_ex == rd_mem) && reg_write_mem;

    // --- 前推数据选择 ---
    always_comb begin
        // 默认值：来自寄存器堆读出的数据
        fwd_data_a = reg_data_A;
        fwd_data_b = reg_data_B;

        // 只有当前指令有效时才考虑前推，否则输出0
        if (valid_ex) begin
            // 选择 A 的前推数据
            if (fwd_a_ex) begin
                // 从 EX 阶段前推：只有当上一条指令不是 Load 时，ALU 结果才有效
                if (mem_to_reg_ex != `MEM_TO_REG_MEM) begin 
                    fwd_data_a = alu_result_ex;
                end
            end 
            else if (fwd_a_mem) begin
                // 从 MEM 阶段前推
                if (mem_to_reg_mem == `MEM_TO_REG_MEM) begin
                    fwd_data_a = mem_data_mem;
                end else begin
                    fwd_data_a = alu_result_mem;
                end
            end

            // 选择 B 的前推数据
            if (fwd_b_ex) begin
                if (mem_to_reg_ex != `MEM_TO_REG_MEM) begin
                    fwd_data_b = alu_result_ex;
                end
            end else if (fwd_b_mem) begin
                if (mem_to_reg_mem == `MEM_TO_REG_MEM) begin
                    fwd_data_b = mem_data_mem;
                end else begin
                    fwd_data_b = alu_result_mem;
                end
            end
        end else begin
            // 当前指令无效，输出清零防止不定态
            fwd_data_a = 32'b0;
            fwd_data_b = 32'b0;
        end
    end
    
    assign fwd_alu_a = fwd_data_a;
    assign fwd_alu_b = fwd_data_b;

endmodule
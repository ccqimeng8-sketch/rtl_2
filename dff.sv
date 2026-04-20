//Program Counter到Control Unit的寄存器
module dff_1 (
    input logic flush,

    input  logic clk,
    input  logic rst,

    input  logic [31:0] in_pc_add4,
    output logic [31:0] out_pc_add4,

    input  logic [31:0] in_pc,
    output logic [31:0] out_pc,

    input  logic [31:0] in_instr,
    output logic [31:0] out_instr,

    input  logic in_valid,
    output logic out_valid
);
    always @(posedge clk) begin
        if (rst || flush) begin
            out_pc_add4 <= 0;
            out_instr <= 32'h00000013;
            out_pc <= 0;
            out_valid <= 0;
        end
        else begin
            out_pc_add4 <= in_pc_add4;
            out_instr <= in_instr;
            out_pc <= in_pc;
            out_valid <= in_valid;
        end
    end
endmodule

//Control Unit和IMMGEN到regfile的寄存器 (实际为 ID/EX 流水线寄存器)
module dff_2(
    input logic flush,

    input  logic clk,
    input  logic rst,

    input  logic [31:0] in_pc_add4,
    output logic [31:0] out_pc_add4,

    input  logic [31:0] in_pc,
    output logic [31:0] out_pc,

    // Control Unit 输出信号
    input  logic [6:0] in_opcode,
    output logic [6:0] out_opcode,

    input  logic [3:0] in_funct,
    output logic [3:0] out_funct,

    input  logic [1:0] in_NpcOp,
    output logic [1:0] out_NpcOp,

    input  logic in_RegWrite,
    output logic out_RegWrite,

    input  logic [2:0] in_MemToReg,
    output logic [2:0] out_MemToReg,

    input  logic in_MemWrite,
    output logic out_MemWrite,

    input  logic [1:0] in_OffsetOrigin,
    output logic [1:0] out_OffsetOrigin,

    input  logic in_ALUSrcA,
    output logic out_ALUSrcA,

    input  logic in_ALUSrcB,
    output logic out_ALUSrcB,

    // IMMGEN 输出信号
    input  logic [31:0] in_imm,
    output logic [31:0] out_imm,

    input  logic [31:0] in_instr,
    output logic [31:0] out_instr,

    input  logic in_valid,
    output logic out_valid,
    
    input logic [31:0] in_ALU_A,
    output logic [31:0] out_ALU_A,

    input logic [31:0] in_ALU_B,
    output logic [31:0] out_ALU_B
);
    always @(posedge clk) begin
        if (rst || flush) begin
            out_NpcOp <= 0;
            out_RegWrite <= 0;
            out_MemToReg <= 0;
            out_MemWrite <= 0;
            out_OffsetOrigin <= 0;
            out_ALUSrcA <= 0;
            out_ALUSrcB <= 0;
            out_imm <= 0;
            out_opcode <= 7'b0010011;
            out_funct <= 0;
            out_pc <= 0;
            out_pc_add4 <= 0;
            out_instr <= 0;
            out_valid <= 0;
            out_ALU_A <= 0;
            out_ALU_B <= 0;
        end
        else begin
            out_NpcOp <= in_NpcOp;
            out_RegWrite <= in_RegWrite;
            out_MemToReg <= in_MemToReg;
            out_MemWrite <= in_MemWrite;
            out_OffsetOrigin <= in_OffsetOrigin;
            out_ALUSrcA <= in_ALUSrcA;
            out_ALUSrcB <= in_ALUSrcB;
            out_imm <= in_imm;
            out_opcode <= in_opcode;
            out_funct <= in_funct;
            out_pc <= in_pc;
            out_pc_add4 <= in_pc_add4;
            out_instr <= in_instr;
            out_valid <= in_valid;
            out_ALU_A <= in_ALU_A;
            out_ALU_B <= in_ALU_B;
        end
    end
endmodule

module dff_3(
    input  logic        clk,
    input  logic        rst,

    // PC+4
    input  logic [31:0] in_pc_add4,
    output logic [31:0] out_pc_add4,

    // 指令相关
    input  logic [31:0] in_instr,
    output logic [31:0] out_instr,
    
    input  logic [3:0]  in_funct,
    output logic [3:0]  out_funct,

    // 控制信号
    input  logic [2:0]  in_MemToReg,
    output logic [2:0]  out_MemToReg,

    input  logic        in_RegWrite,
    output logic        out_RegWrite,

    input  logic        in_MemWrite,
    output logic        out_MemWrite,

    // 数据通路信号
    input  logic [31:0] in_daddr,       // ALU 结果
    output logic [31:0] out_daddr,

    input  logic [31:0] in_ALU_B,
    output logic [31:0] out_ALU_B,

    input  logic [31:0] in_imm,         // 立即数
    output logic [31:0] out_imm,

    input  logic in_valid,
    output logic out_valid,

    input  logic in_isTrue,
    output logic out_isTrue,

    input  logic [1:0] in_OffsetOrigin,
    output logic [1:0] out_OffsetOrigin,

    input  logic [31:0] in_pc,
    output logic [31:0] out_pc
    );
 
    always @(posedge clk) begin
        if (rst) begin
            out_pc_add4   <= 0;
            out_instr     <= 0;
            out_funct     <= 0;
            out_MemToReg  <= 0;
            out_RegWrite  <= 0;
            out_MemWrite  <= 0;
            out_daddr     <= 0;
            out_imm       <= 0;
            out_ALU_B     <= 0;
            out_valid     <= 0;
            out_isTrue   <= 0;
            out_OffsetOrigin <= 0;
            out_pc        <= 0;
        end
        else begin
            out_pc_add4   <= in_pc_add4;
            out_instr     <= in_instr;
            out_funct     <= in_funct;
            out_MemToReg  <= in_MemToReg;
            out_RegWrite  <= in_RegWrite;
            out_MemWrite  <= in_MemWrite;
            out_daddr     <= in_daddr;
            out_imm       <= in_imm;
            out_ALU_B     <= in_ALU_B;
            out_valid     <= in_valid;
            out_isTrue    <= in_isTrue;
            out_OffsetOrigin <= in_OffsetOrigin;
            out_pc        <= in_pc;
        end
    end
endmodule

// 写回多路选择器的寄存器
module dff_4(
    input  logic clk,
    input  logic rst,

    // 控制信号：决定写回数据的来源
    input  logic [2:0] in_MemToReg,
    output logic [2:0] out_MemToReg,

    // 数据源 1: PC + 4
    input  logic [31:0] in_pc_add4,
    output logic [31:0] out_pc_add4,

    // 数据源 2: ALU 结果 (daddr)
    input  logic [31:0] in_daddr,
    output logic [31:0] out_daddr,

    // 数据源 3: 立即数 (imm)
    input  logic [31:0] in_imm,
    output logic [31:0] out_imm,

    // 数据源 4: CSR 写回数据 (csr_wb)
    //input  logic [31:0] in_csr_wb,
    //output logic [31:0] out_csr_wb,

    input  logic        in_RegWrite,
    output logic        out_RegWrite,

    input  logic [31:0] in_instr,
    output logic [31:0] out_instr,

    input  logic [31:0] in_mdata,
    output logic [31:0] out_mdata,

    input  logic in_valid,
    output logic out_valid
);
    always @(posedge clk) begin
        if (rst) begin
            out_MemToReg <= 0;
            out_pc_add4   <= 0;
            out_daddr    <= 0;
            out_imm      <= 0;
            //out_csr_wb   <= 0;
            out_RegWrite <= 0;
            out_instr    <= 0;
            out_mdata    <= 0;
            out_valid    <= 0;
        end
        else begin
            out_MemToReg <= in_MemToReg;
            out_pc_add4   <= in_pc_add4;
            out_daddr    <= in_daddr;
            out_imm      <= in_imm;
            //out_csr_wb   <= in_csr_wb;
            out_RegWrite <= in_RegWrite;
            out_instr    <= in_instr;
            out_mdata    <= in_mdata;
            out_valid    <= in_valid;
        end
    end
endmodule
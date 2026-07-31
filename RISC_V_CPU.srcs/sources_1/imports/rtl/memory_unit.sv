// ============================================================================
// 模块名 : memory_unit
// 项目  : RISC-V 双发射超标量处理器（优化版）
// 描述  : 双通道访存单元，带双端口数据存储器。
//        - 支持 LB/LH/LW/LBU/LHU（加载）和 SB/SH/SW（存储）
//        - 每个通道有各自独立的存储器端口
//        - 基于地址和访问宽度生成字节使能
//        - 存储数据对齐（根据地址偏移进行移位）
//        - 加载数据对齐和符号/零扩展
//        - 双端口：Lane 0 和 Lane 1 独立访存
// ============================================================================

`include "defines.sv"
`include "types.sv"

module memory_unit (
    input  logic        clk,            // 时钟
    input  logic        rst_n,          // 同步复位，低有效

    // ----- 来自 EX/MEM 流水线寄存器的输入 -----
    input  ex_mem_reg_t ex_mem_in,      // ALU 结果 + 控制信号

    // ----- 数据存储器端口 0（Lane 0，32 位）-----
    output logic [31:0] dmem_addr0,     // Lane 0 访存地址
    output logic [31:0] dmem_wdata0,    // Lane 0 写数据（已对齐）
    output logic        dmem_we0,       // Lane 0 写使能
    output logic [3:0]  dmem_be0,       // Lane 0 字节使能
    input  logic [31:0] dmem_rdata0,    // Lane 0 读数据

    // ----- 数据存储器端口 1（Lane 1，32 位）-----
    output logic [31:0] dmem_addr1,     // Lane 1 访存地址
    output logic [31:0] dmem_wdata1,    // Lane 1 写数据（已对齐）
    output logic        dmem_we1,       // Lane 1 写使能
    output logic [3:0]  dmem_be1,       // Lane 1 字节使能
    input  logic [31:0] dmem_rdata1,    // Lane 1 读数据

    // ----- 输出至 MEM/WB 流水线寄存器 -----
    output mem_wb_reg_t mem_wb_out       // 双通道写回数据
);

    // ========================================================================
    // Lane 0 访存逻辑
    // ========================================================================

    // 地址来自 ALU 结果（在 EX 级计算）
    logic [31:0] addr0;
    assign addr0 = ex_mem_in.alu_result0;

    // Lane 0 字节使能生成
    logic [3:0] be0;
    always_comb begin
        case (ex_mem_in.mem_width0[1:0])
            `MEM_WIDTH_BYTE: be0 = 4'b0001 << addr0[1:0]; // 1 字节
            `MEM_WIDTH_HALF: be0 = 4'b0011 << addr0[1:0]; // 2 字节（半字）
            `MEM_WIDTH_WORD: be0 = 4'b1111;                // 4 字节（字）
            default:         be0 = 4'b0000;
        endcase
    end

    // Lane 0 存储数据对齐
    logic [31:0] store_data0;
    always_comb begin
        case (addr0[1:0])
            2'b00: store_data0 = ex_mem_in.rs2_data0;
            2'b01: store_data0 = {ex_mem_in.rs2_data0[23:0], ex_mem_in.rs2_data0[31:24]};
            2'b10: store_data0 = {ex_mem_in.rs2_data0[15:0], ex_mem_in.rs2_data0[31:16]};
            2'b11: store_data0 = {ex_mem_in.rs2_data0[7:0],  ex_mem_in.rs2_data0[31:24]};
        endcase
    end

    // Lane 0 加载数据对齐与符号/零扩展
    logic [31:0] load_data0;
    logic sign_ext0;
    assign sign_ext0 = ex_mem_in.mem_sign0; // 1 = 符号扩展, 0 = 零扩展

    always_comb begin
        case (ex_mem_in.mem_width0[1:0])
            `MEM_WIDTH_BYTE: begin // 字节加载
                case (addr0[1:0])
                    2'b00: load_data0 = {{24{sign_ext0 & dmem_rdata0[7]}},  dmem_rdata0[7:0]};
                    2'b01: load_data0 = {{24{sign_ext0 & dmem_rdata0[15]}}, dmem_rdata0[15:8]};
                    2'b10: load_data0 = {{24{sign_ext0 & dmem_rdata0[23]}}, dmem_rdata0[23:16]};
                    2'b11: load_data0 = {{24{sign_ext0 & dmem_rdata0[31]}}, dmem_rdata0[31:24]};
                endcase
            end
            `MEM_WIDTH_HALF: begin // 半字加载
                case (addr0[1])
                    1'b0: load_data0 = {{16{sign_ext0 & dmem_rdata0[15]}}, dmem_rdata0[15:0]};
                    1'b1: load_data0 = {{16{sign_ext0 & dmem_rdata0[31]}}, dmem_rdata0[31:16]};
                endcase
            end
            `MEM_WIDTH_WORD: begin // 字加载
                load_data0 = dmem_rdata0;
            end
            default: begin
                load_data0 = 32'b0;
            end
        endcase
    end

    // Lane 0 写回数据选择
    logic [31:0] wb_data0;
    assign wb_data0 = ex_mem_in.mem_read0 ? load_data0 : ex_mem_in.alu_result0;

    // ========================================================================
    // Lane 1 访存逻辑（独立端口）
    // ========================================================================

    logic [31:0] addr1;
    assign addr1 = ex_mem_in.alu_result1;

    // Lane 1 字节使能生成
    logic [3:0] be1;
    always_comb begin
        case (ex_mem_in.mem_width1[1:0])
            `MEM_WIDTH_BYTE: be1 = 4'b0001 << addr1[1:0];
            `MEM_WIDTH_HALF: be1 = 4'b0011 << addr1[1:0];
            `MEM_WIDTH_WORD: be1 = 4'b1111;
            default:         be1 = 4'b0000;
        endcase
    end

    // Lane 1 存储数据对齐
    logic [31:0] store_data1;
    always_comb begin
        case (addr1[1:0])
            2'b00: store_data1 = ex_mem_in.rs2_data1;
            2'b01: store_data1 = {ex_mem_in.rs2_data1[23:0], ex_mem_in.rs2_data1[31:24]};
            2'b10: store_data1 = {ex_mem_in.rs2_data1[15:0], ex_mem_in.rs2_data1[31:16]};
            2'b11: store_data1 = {ex_mem_in.rs2_data1[7:0],  ex_mem_in.rs2_data1[31:24]};
        endcase
    end

    // Lane 1 加载数据（使用独立的 dmem_rdata1 端口）
    logic [31:0] load_data1;
    logic sign_ext1;
    assign sign_ext1 = ex_mem_in.mem_sign1;

    always_comb begin
        case (ex_mem_in.mem_width1[1:0])
            `MEM_WIDTH_BYTE: begin
                case (addr1[1:0])
                    2'b00: load_data1 = {{24{sign_ext1 & dmem_rdata1[7]}},  dmem_rdata1[7:0]};
                    2'b01: load_data1 = {{24{sign_ext1 & dmem_rdata1[15]}}, dmem_rdata1[15:8]};
                    2'b10: load_data1 = {{24{sign_ext1 & dmem_rdata1[23]}}, dmem_rdata1[23:16]};
                    2'b11: load_data1 = {{24{sign_ext1 & dmem_rdata1[31]}}, dmem_rdata1[31:24]};
                endcase
            end
            `MEM_WIDTH_HALF: begin
                case (addr1[1])
                    1'b0: load_data1 = {{16{sign_ext1 & dmem_rdata1[15]}}, dmem_rdata1[15:0]};
                    1'b1: load_data1 = {{16{sign_ext1 & dmem_rdata1[31]}}, dmem_rdata1[31:16]};
                endcase
            end
            `MEM_WIDTH_WORD: begin
                load_data1 = dmem_rdata1;
            end
            default: begin
                load_data1 = 32'b0;
            end
        endcase
    end

    logic [31:0] wb_data1;
    assign wb_data1 = ex_mem_in.mem_read1 ? load_data1 : ex_mem_in.alu_result1;

    // ========================================================================
    // 数据存储器端口 0 输出（Lane 0 - 独立）
    // ========================================================================
    assign dmem_addr0  = (ex_mem_in.mem_read0 || ex_mem_in.mem_write0) ? addr0 : 32'b0;
    assign dmem_wdata0 = store_data0;
    assign dmem_we0    = ex_mem_in.mem_write0 & ex_mem_in.valid0;
    assign dmem_be0    = be0;

    // ========================================================================
    // 数据存储器端口 1 输出（Lane 1 - 独立）
    // ========================================================================
    assign dmem_addr1  = (ex_mem_in.mem_read1 || ex_mem_in.mem_write1) ? addr1 : 32'b0;
    assign dmem_wdata1 = store_data1;
    assign dmem_we1    = ex_mem_in.mem_write1 & ex_mem_in.valid1;
    assign dmem_be1    = be1;

    // ========================================================================
    // MEM/WB 输出组装
    // ========================================================================
    always_comb begin
        // Lane 0
        mem_wb_out.write_data0 = wb_data0;
        mem_wb_out.rd_addr0    = ex_mem_in.rd_addr0;
        mem_wb_out.reg_write0  = ex_mem_in.reg_write0 & ex_mem_in.valid0;
        mem_wb_out.valid0      = ex_mem_in.valid0;

        // Lane 1
        mem_wb_out.write_data1 = wb_data1;
        mem_wb_out.rd_addr1    = ex_mem_in.rd_addr1;
        mem_wb_out.reg_write1  = ex_mem_in.reg_write1 & ex_mem_in.valid1;
        mem_wb_out.valid1      = ex_mem_in.valid1;
    end

endmodule

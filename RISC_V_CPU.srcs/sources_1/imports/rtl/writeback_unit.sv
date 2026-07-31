// ============================================================================
// 模块 : writeback_unit
// 项目 : RISC-V 双发射超标量处理器
// 说明 : 写回单元，将结果写入寄存器文件。
//        - 2个写端口（Lane 0 和 Lane 1）
//        - Lane 0 具有优先级；x0 的写入被抑制
//        - 同一 rd 在两个通道中的写冲突由冒险单元
//          在译码阶段阻塞 Lane 1 来防止
// ============================================================================

`include "defines.sv"
`include "types.sv"

module writeback_unit (
    input  logic        clk,            // 时钟（未使用，纯组合逻辑）
    input  logic        rst_n,          // 同步复位（未使用）

    // ----- 来自 MEM/WB 流水线寄存器的输入 -----
    input  mem_wb_reg_t mem_wb_in,      // 两个通道的最终写回数据

    // ----- 寄存器文件写端口 0（Lane 0）-----
    output logic [4:0]  rf_waddr0,      // Lane 0 写地址
    output logic [31:0] rf_wdata0,      // Lane 0 写数据
    output logic        rf_we0,         // Lane 0 写使能

    // ----- 寄存器文件写端口 1（Lane 1）-----
    output logic [4:0]  rf_waddr1,      // Lane 1 写地址
    output logic [31:0] rf_wdata1,      // Lane 1 写数据
    output logic        rf_we1          // Lane 1 写使能
);

    // ========================================================================
    // Lane 0 写回
    // ========================================================================
    // 在以下条件满足时写入寄存器文件：
    //   - reg_write 有效
    //   - 通道有效
    //   - 目标寄存器不是 x0（x0 硬连线为0）

    assign rf_waddr0 = mem_wb_in.rd_addr0;
    assign rf_wdata0 = mem_wb_in.write_data0;
    assign rf_we0    = mem_wb_in.reg_write0 &
                       mem_wb_in.valid0 &
                       (mem_wb_in.rd_addr0 != 5'b0);

    // ========================================================================
    // Lane 1 写回
    // ========================================================================
    // 条件与 Lane 0 相同。
    // 注意：如果两个通道写入同一个寄存器，冒险单元应在译码阶段
    // 阻塞 Lane 1。作为安全措施，寄存器文件也会检查地址冲突。

    assign rf_waddr1 = mem_wb_in.rd_addr1;
    assign rf_wdata1 = mem_wb_in.write_data1;
    assign rf_we1    = mem_wb_in.reg_write1 &
                       mem_wb_in.valid1 &
                       (mem_wb_in.rd_addr1 != 5'b0);

endmodule

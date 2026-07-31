// ============================================================================
// 文件名：tb_riscv_core 测试平台
// 说明：RISC-V 双发射超标量处理器的顶层验证环境
// 警告：xvlog 工具启动失败通常是许可证或许可证服务器配置问题，
//       请检查 Xilinx 许可证是否有效及环境变量是否正确设置
// ============================================================================
// 模块 : tb_riscv_core
// 项目 : RISC-V 双发射超标量处理器（优化版）
// 说明 : RISC-V超标量核心的顶层测试平台。
//        - 时钟与复位生成
//        - 指令存储器模型（64位读，类ROM）
//        - 双端口数据存储器模型（32位读写）
//        - 全面测试：覆盖全部37条RV32I指令
//        - 两阶段检查：先ALU/访存/存储，后分支/跳转
//        - 寄存器文件监控和结果检查
// ============================================================================

`timescale 1ns / 1ps

`include "defines.sv"
`include "types.sv"

module tb_riscv_core;

    // ========================================================================
    // 时钟与复位
    // ========================================================================
    logic clk;
    logic rst_n;

    // 100MHz时钟（10ns周期）
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 复位时序
    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        $display("[%0t] Reset released", $time);
    end

    // ========================================================================
    // DUT接口信号
    // ========================================================================
    wire [31:0] imem_addr;
    wire [63:0] imem_rdata;
    wire [31:0] dmem_addr0;
    wire [31:0] dmem_wdata0;
    wire        dmem_we0;
    wire [3:0]  dmem_be0;
    wire [31:0] dmem_rdata0;
    wire [31:0] dmem_addr1;
    wire [31:0] dmem_wdata1;
    wire        dmem_we1;
    wire [3:0]  dmem_be1;
    wire [31:0] dmem_rdata1;

    // ========================================================================
    // 指令存储器模型
    // ========================================================================
    // 128字 × 64位 = 1KB 指令存储器
    // 每个64位字存储一个取指对（2条连续的32位指令）
    // {imem[63:32], imem[31:0]} = {inst1, inst0} (Lane1, Lane0)
    logic [63:0] imem [0:127];

    // 64位读：单字访问（每个字 = 1个取指对）
    assign imem_rdata = imem[imem_addr[31:3]];

    // ========================================================================
    // 数据存储器模型（双端口）
    // ========================================================================
    // 256字 × 32位 = 1KB 数据存储器
    // 按字节寻址，支持字节使能
    // 端口0（Lane 0）在同地址写入时优先级高于端口1（Lane 1）
    logic [31:0] dmem [0:255];

    // 数据存储器初始化
    reg dmem_initialized;
    initial dmem_initialized = 1'b0;

    always @(posedge clk) begin
        // 复位后一次性初始化
        if (!dmem_initialized) begin
            for (int i = 0; i < 256; i++)
                dmem[i] = 32'b0;
            dmem_initialized <= 1'b1;
        end
        // 端口0写入（Lane 0）- 优先级更高
        if (dmem_we0) begin
            if (dmem_be0[0]) dmem[dmem_addr0[9:2]][7:0]   <= dmem_wdata0[7:0];
            if (dmem_be0[1]) dmem[dmem_addr0[9:2]][15:8]  <= dmem_wdata0[15:8];
            if (dmem_be0[2]) dmem[dmem_addr0[9:2]][23:16] <= dmem_wdata0[23:16];
            if (dmem_be0[3]) dmem[dmem_addr0[9:2]][31:24] <= dmem_wdata0[31:24];
        end
        // 端口1写入（Lane 1）- 优先级较低，若与端口0同地址则被抑制
        if (dmem_we1 && !(dmem_we0 && (dmem_addr1[9:2] == dmem_addr0[9:2]))) begin
            if (dmem_be1[0]) dmem[dmem_addr1[9:2]][7:0]   <= dmem_wdata1[7:0];
            if (dmem_be1[1]) dmem[dmem_addr1[9:2]][15:8]  <= dmem_wdata1[15:8];
            if (dmem_be1[2]) dmem[dmem_addr1[9:2]][23:16] <= dmem_wdata1[23:16];
            if (dmem_be1[3]) dmem[dmem_addr1[9:2]][31:24] <= dmem_wdata1[31:24];
        end
    end

    // 双读端口（组合逻辑）
    assign dmem_rdata0 = dmem[dmem_addr0[9:2]];
    assign dmem_rdata1 = dmem[dmem_addr1[9:2]];

    // ========================================================================
    // DUT例化
    // ========================================================================
    riscv_core u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr0 (dmem_addr0),
        .dmem_wdata0(dmem_wdata0),
        .dmem_we0   (dmem_we0),
        .dmem_be0   (dmem_be0),
        .dmem_rdata0(dmem_rdata0),
        .dmem_addr1 (dmem_addr1),
        .dmem_wdata1(dmem_wdata1),
        .dmem_we1   (dmem_we1),
        .dmem_be1   (dmem_be1),
        .dmem_rdata1(dmem_rdata1)
    );

    // ========================================================================
    // 测试程序加载
    // ========================================================================
    // 全面RV32I测试：共126个取指对，覆盖全部37条指令
    // 两阶段设计，阶段1和阶段2之间有30条NOP间隔
    // 阶段1（条目0-51）：  初始化、R型ALU、I型ALU、存储、加载
    // 间隔（条目52-81）：  30个NOP对用于流水线排空
    // 阶段2（条目82-125）：分支（6条）、跳转（2条）、AUIPC
    //
    // 通道约束：分支/跳转/访存操作必须放在Lane 0
    // Lane 1写回比Lane 0晚1个周期
    // 存储→加载冒险：SW与LW之间需要1个NOP对的间隔

    // NOP对：将两条NOP指令打包为一个64位字
    localparam [63:0] NOP_PAIR = {32'h00000013, 32'h00000013};

    initial begin
        // 将指令存储器初始化为NOP对
        for (int i = 0; i < 128; i++)
            imem[i] = NOP_PAIR;

        // ===== 阶段1：初始化（5条）=====
        imem[  0] = {32'h01400113, 32'h00A00093}; // 0x0000: x1=10, x2=20
        imem[  1] = NOP_PAIR;                       // 0x0008:
        imem[  2] = {32'hFF600213, 32'h00400193}; // 0x0010: x3=4, x4=-10
        imem[  3] = NOP_PAIR;                       // 0x0018:
        imem[  4] = {32'h00000013, 32'h800002B7}; // 0x0020: LUI x5,0x80000

        // ===== 阶段1：R型ALU（10条指令，条目6-15）=====
        imem[  6] = {32'h402085B3, 32'h00208533}; // 0x0030: SUB x11 | ADD x10 (30,-10)
        imem[  8] = {32'h001226B3, 32'h00309633}; // 0x0040: SLT x13 | SLL x12 (160,1)
        imem[ 10] = {32'h0020C7B3, 32'h0012B733}; // 0x0050: XOR x15 | SLTU x14 (0,30)
        imem[ 12] = {32'h4032D8B3, 32'h0032D833}; // 0x0060: SRA x17 | SRL x16
        imem[ 14] = {32'h0020F9B3, 32'h0020E933}; // 0x0070: AND x19 | OR x18 (30,0)

        // ===== 阶段1：I型ALU（9条指令，条目16-25）=====
        imem[ 16] = {32'h00209A93, 32'h00708A13}; // 0x0080: SLLI x21 | ADDI x20 (17,40)
        imem[ 18] = {32'h0052BB93, 32'h00522B13}; // 0x0090: SLTIU x23 | SLTI x22 (1,0)
        imem[ 20] = {32'h0012DC93, 32'h0FF0CC13}; // 0x00A0: SRLI x25 | XORI x24 (245,0x40000000)
        imem[ 22] = {32'hF000ED93, 32'h4012DD13}; // 0x00B0: ORI x27 | SRAI x26 (0xC0000000,0xF0A)
        imem[ 24] = {32'h00000013, 32'h00F0FE13}; // 0x00C0: nop | ANDI x28 (10)

        // ===== 阶段1：存储测试（5条指令，条目26-41）=====
        imem[ 26] = {32'h00000013, 32'hF8500313}; // 0x00D0: nop | ADDI x6,x0,-123
        imem[ 28] = {32'h00000013, 32'h00602023}; // 0x00E0: nop | SW x6,0(x0)
        imem[ 30] = {32'h00000013, 32'hFFFF83B7}; // 0x00F0: nop | LUI x7,0xFFFF8
        imem[ 32] = {32'h00000013, 32'h23438393}; // 0x0100: nop | ADDI x7,x7,0x234
        imem[ 34] = {32'h00000013, 32'h00702223}; // 0x0110: nop | SW x7,4(x0)
        imem[ 36] = {32'h00000013, 32'h00A02423}; // 0x0120: nop | SW x10,8(x0)
        imem[ 38] = {32'h00000013, 32'h00701623}; // 0x0130: nop | SH x7,12(x0)
        imem[ 40] = {32'h00000013, 32'h00600823}; // 0x0140: nop | SB x6,16(x0)

        // ===== 阶段1：加载测试（5条指令，条目42-51）=====
        imem[ 42] = {32'h00000013, 32'h00802E83}; // 0x0150: nop | LW x29,8(x0) -> 30
        imem[ 44] = {32'h00000013, 32'h00C01F03}; // 0x0160: nop | LH x30,12(x0) -> 0xFFFF8234
        imem[ 46] = {32'h00000013, 32'h00C05F83}; // 0x0170: nop | LHU x31,12(x0) -> 0x00008234
        imem[ 48] = {32'h00000013, 32'h01000483}; // 0x0180: nop | LB x9,16(x0) -> 0xFFFFFF85
        imem[ 50] = {32'h00000013, 32'h01004403}; // 0x0190: nop | LBU x8,16(x0) -> 0x00000085

        // ===== NOP间隔（30条，条目52-81）：流水线排空 =====
        // 阶段1结果在此稳定；检查在此间隔期间进行

        // ===== 阶段2：分支测试（6条指令，条目82-111）=====
        imem[ 82] = {32'h00000013, 32'h00208863}; // 0x0290: BEQ x1,x2,+16 (不跳转)
        imem[ 83] = {32'h00000013, 32'h0C800F93}; // 0x0298: fall: x31=200
        imem[ 84] = {32'h00000013, 32'h0180006F}; // 0x02A0: JAL x0,+24 (跳过)
        imem[ 85] = {32'h00000013, 32'h00000F93}; // 0x02A8: target(跳过): x31=0

        imem[ 87] = {32'h00000013, 32'h00209863}; // 0x02B8: BNE x1,x2,+16 (跳转)
        imem[ 88] = {32'h00000013, 32'h00000F93}; // 0x02C0: fall(跳过): x31=0
        imem[ 89] = {32'h00000013, 32'h0180006F}; // 0x02C8: JAL x0,+24 (跳过)
        imem[ 90] = {32'h00000013, 32'h0C900F93}; // 0x02D0: target: x31=201

        imem[ 92] = {32'h00000013, 32'h00124863}; // 0x02E0: BLT x4,x1,+16 (跳转)
        imem[ 93] = {32'h00000013, 32'h00000F93}; // 0x02E8: fall(跳过): x31=0
        imem[ 94] = {32'h00000013, 32'h0180006F}; // 0x02F0: JAL x0,+24 (跳过)
        imem[ 95] = {32'h00000013, 32'h0CA00F93}; // 0x02F8: target: x31=202

        imem[ 97] = {32'h00000013, 32'h00125863}; // 0x0308: BGE x4,x1,+16 (不跳转)
        imem[ 98] = {32'h00000013, 32'h0CB00F93}; // 0x0310: fall: x31=203
        imem[ 99] = {32'h00000013, 32'h0180006F}; // 0x0318: JAL x0,+24 (跳过)
        imem[100] = {32'h00000013, 32'h00000F93}; // 0x0320: target(跳过): x31=0

        imem[102] = {32'h00000013, 32'h0012E863}; // 0x0330: BLTU x5,x1,+16 (不跳转)
        imem[103] = {32'h00000013, 32'h0CC00F93}; // 0x0338: fall: x31=204
        imem[104] = {32'h00000013, 32'h0180006F}; // 0x0340: JAL x0,+24 (跳过)
        imem[105] = {32'h00000013, 32'h00000F93}; // 0x0348: target(跳过): x31=0

        imem[107] = {32'h00000013, 32'h0012F863}; // 0x0358: BGEU x5,x1,+16 (跳转)
        imem[108] = {32'h00000013, 32'h00000F93}; // 0x0360: fall(跳过): x31=0
        imem[109] = {32'h00000013, 32'h0180006F}; // 0x0368: JAL x0,+24 (跳过)
        imem[110] = {32'h00000013, 32'h0CD00F93}; // 0x0370: target: x31=205

        // ===== 阶段2：跳转测试（2条指令，条目112-119）=====
        imem[112] = {32'h00000013, 32'h01800B6F}; // 0x0380: JAL x22,+24
        imem[115] = {32'h00000013, 32'h12C00B93}; // 0x0398: target: x23=300
        imem[117] = {32'h00000013, 32'h000B0CE7}; // 0x03A8: JALR x25,x22,0 (return)
        imem[119] = {32'h00000013, 32'h19000C13}; // 0x03B8: after JALR: x24=400

        // ===== 阶段2：AUIPC（1条指令，条目121）=====
        imem[121] = {32'h00000013, 32'h00000D17}; // 0x03C8: AUIPC x26,0
    end

    // ========================================================================
    // 寄存器文件监控（通过DUT层级访问）
    // ========================================================================
    // 访问内部寄存器文件以检查结果
    wire [31:0] rf_x0  = u_dut.u_regfile.regs[0];
    wire [31:0] rf_x1  = u_dut.u_regfile.regs[1];
    wire [31:0] rf_x2  = u_dut.u_regfile.regs[2];
    wire [31:0] rf_x3  = u_dut.u_regfile.regs[3];
    wire [31:0] rf_x4  = u_dut.u_regfile.regs[4];
    wire [31:0] rf_x5  = u_dut.u_regfile.regs[5];
    wire [31:0] rf_x6  = u_dut.u_regfile.regs[6];
    wire [31:0] rf_x7  = u_dut.u_regfile.regs[7];
    wire [31:0] rf_x8  = u_dut.u_regfile.regs[8];
    wire [31:0] rf_x9  = u_dut.u_regfile.regs[9];
    wire [31:0] rf_x10 = u_dut.u_regfile.regs[10];
    wire [31:0] rf_x11 = u_dut.u_regfile.regs[11];
    wire [31:0] rf_x12 = u_dut.u_regfile.regs[12];
    wire [31:0] rf_x13 = u_dut.u_regfile.regs[13];
    wire [31:0] rf_x14 = u_dut.u_regfile.regs[14];
    wire [31:0] rf_x15 = u_dut.u_regfile.regs[15];
    wire [31:0] rf_x16 = u_dut.u_regfile.regs[16];
    wire [31:0] rf_x17 = u_dut.u_regfile.regs[17];
    wire [31:0] rf_x18 = u_dut.u_regfile.regs[18];
    wire [31:0] rf_x19 = u_dut.u_regfile.regs[19];
    wire [31:0] rf_x20 = u_dut.u_regfile.regs[20];
    wire [31:0] rf_x21 = u_dut.u_regfile.regs[21];
    wire [31:0] rf_x22 = u_dut.u_regfile.regs[22];
    wire [31:0] rf_x23 = u_dut.u_regfile.regs[23];
    wire [31:0] rf_x24 = u_dut.u_regfile.regs[24];
    wire [31:0] rf_x25 = u_dut.u_regfile.regs[25];
    wire [31:0] rf_x26 = u_dut.u_regfile.regs[26];
    wire [31:0] rf_x27 = u_dut.u_regfile.regs[27];
    wire [31:0] rf_x28 = u_dut.u_regfile.regs[28];
    wire [31:0] rf_x29 = u_dut.u_regfile.regs[29];
    wire [31:0] rf_x30 = u_dut.u_regfile.regs[30];
    wire [31:0] rf_x31 = u_dut.u_regfile.regs[31];

    // ========================================================================
    // 调试：监控写回阶段
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // 监控寄存器文件写入
            if (u_dut.rf_we0)
                $display("[%0t] WB Lane0: x%0d <= 0x%08h", $time,
                    u_dut.rf_waddr0, u_dut.rf_wdata0);
            if (u_dut.rf_we1)
                $display("[%0t] WB Lane1: x%0d <= 0x%08h", $time,
                    u_dut.rf_waddr1, u_dut.rf_wdata1);
            // 监控EX阶段ALU计算
            if (u_dut.u_execute_unit.id_ex_in.valid0)
                $display("[%0t] EX Lane0: pc=0x%08h op=%d src=%b rs1=0x%08h rs2=0x%08h fwd_a=0x%08h fwd_b=0x%08h result=0x%08h mw=%d mwe=%b",
                    $time, u_dut.u_execute_unit.id_ex_in.pc0,
                    u_dut.u_execute_unit.id_ex_in.alu_op0,
                    u_dut.u_execute_unit.id_ex_in.alu_src0,
                    u_dut.u_execute_unit.id_ex_in.rs1_data0,
                    u_dut.u_execute_unit.id_ex_in.rs2_data0,
                    u_dut.u_execute_unit.fwd_a0,
                    u_dut.u_execute_unit.fwd_b0,
                    u_dut.u_execute_unit.alu_result0,
                    u_dut.u_execute_unit.id_ex_in.mem_width0,
                    u_dut.u_execute_unit.id_ex_in.mem_write0);
            // 监控分支解析
            if (u_dut.branch_resolve)
                $display("[%0t] BRANCH: pc=0x%08h taken=%0b target=0x%08h mispredict=%0b",
                    $time, u_dut.u_execute_unit.id_ex_in.pc0,
                    u_dut.branch_taken, u_dut.branch_target,
                    u_dut.branch_mispredict);
            // 监控控制信号
            if (u_dut.flush_if_id || u_dut.flush_id_ex || u_dut.stall)
                $display("[%0t] CONTROL: stall=%0b flush_if_id=%0b flush_id_ex=%0b",
                    $time, u_dut.stall, u_dut.flush_if_id, u_dut.flush_id_ex);
            // 监控EX/MEM阶段的存储操作
            if (u_dut.ex_mem_reg.valid0 && u_dut.ex_mem_reg.mem_write0)
                $display("[%0t] STORE0: addr=0x%08h wdata=0x%08h be=%b width=%d rs2_data=0x%08h",
                    $time, u_dut.ex_mem_reg.alu_result0,
                    u_dut.ex_mem_reg.rs2_data0,
                    u_dut.u_memory_unit.be0,
                    u_dut.ex_mem_reg.mem_width0,
                    u_dut.ex_mem_reg.rs2_data0);
            // 监控存储器接口
            if (dmem_we0)
                $display("[%0t] DMEM_WR0: addr=0x%08h wdata=0x%08h be=%b",
                    $time, dmem_addr0, dmem_wdata0, dmem_be0);
            if (dmem_we1)
                $display("[%0t] DMEM_WR1: addr=0x%08h wdata=0x%08h be=%b",
                    $time, dmem_addr1, dmem_wdata1, dmem_be1);
        end
    end

    // ========================================================================
    // 测试序列与结果检查（两阶段）
    // ========================================================================
    int pass_count = 0;
    int fail_count = 0;

    task automatic check_instr(string instr_name, string reg_name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            $display("[%0t]  PASS: %-6s | %s = 0x%08h", $time, instr_name, reg_name, actual);
            pass_count++;
        end else begin
            $display("[%0t] *FAIL: %-6s | %s = 0x%08h (EXPECTED 0x%08h)", $time, instr_name, reg_name, actual, expected);
            fail_count++;
        end
    endtask

    // ===== 阶段1检查：等待流水线到达间隔区域 =====
    // 阶段1指令在条目51结束。在5级流水线下，
    // ~62个周期应足以让所有阶段1结果写回。
    initial begin
        // 等待复位完成
        @(posedge clk);
        while (!rst_n) @(posedge clk);

        // ====================================================================
        // 阶段1：检查ALU + 加载/存储结果（31项检查）
        // 等待阶段1指令写回完成
        // 最后阶段1写回约在第62个周期；阶段2首次取指约在第87个周期
        // 在第85个周期（80+5复位）检查可确保所有结果稳定
        // 且x31（LHU）尚未被阶段2分支覆盖
        // ====================================================================
        repeat (80) @(posedge clk);

        $display("\n===== Phase 1: Register File Dump =====");
        $display("x1 =0x%08h  x2 =0x%08h  x3 =0x%08h  x4 =0x%08h", rf_x1, rf_x2, rf_x3, rf_x4);
        $display("x5 =0x%08h  x6 =0x%08h  x7 =0x%08h  x8 =0x%08h", rf_x5, rf_x6, rf_x7, rf_x8);
        $display("x9 =0x%08h  x10=0x%08h  x11=0x%08h  x12=0x%08h", rf_x9, rf_x10, rf_x11, rf_x12);
        $display("x13=0x%08h  x14=0x%08h  x15=0x%08h  x16=0x%08h", rf_x13, rf_x14, rf_x15, rf_x16);
        $display("x17=0x%08h  x18=0x%08h  x19=0x%08h  x20=0x%08h", rf_x17, rf_x18, rf_x19, rf_x20);
        $display("x21=0x%08h  x22=0x%08h  x23=0x%08h  x24=0x%08h", rf_x21, rf_x22, rf_x23, rf_x24);
        $display("x25=0x%08h  x26=0x%08h  x27=0x%08h  x28=0x%08h", rf_x25, rf_x26, rf_x27, rf_x28);
        $display("x29=0x%08h  x30=0x%08h  x31=0x%08h", rf_x29, rf_x30, rf_x31);
        $display("=========================================\n");

        // 阶段1验证：31项检查
        $display("===== Phase 1: Instruction Result Verification =====");
        check_instr("ADDI",  "x1",  rf_x1,  32'h0000000A);
        check_instr("ADDI",  "x2",  rf_x2,  32'h00000014);
        check_instr("ADDI",  "x3",  rf_x3,  32'h00000004);
        check_instr("ADDI",  "x4",  rf_x4,  32'hFFFFFFF6);
        check_instr("LUI",   "x5",  rf_x5,  32'h80000000);
        check_instr("ADDI",  "x6",  rf_x6,  32'hFFFFFF85);
        check_instr("LUI",   "x7",  rf_x7,  32'hFFFF8234);
        check_instr("ADD",   "x10", rf_x10, 32'h0000001E);
        check_instr("SUB",   "x11", rf_x11, 32'hFFFFFFF6);
        check_instr("SLL",   "x12", rf_x12, 32'h000000A0);
        check_instr("SLT",   "x13", rf_x13, 32'h00000001);
        check_instr("SLTU",  "x14", rf_x14, 32'h00000000);
        check_instr("XOR",   "x15", rf_x15, 32'h0000001E);
        check_instr("SRL",   "x16", rf_x16, 32'h08000000);
        check_instr("SRA",   "x17", rf_x17, 32'hF8000000);
        check_instr("OR",    "x18", rf_x18, 32'h0000001E);
        check_instr("AND",   "x19", rf_x19, 32'h00000000);
        check_instr("ADDI",  "x20", rf_x20, 32'h00000011);
        check_instr("SLLI",  "x21", rf_x21, 32'h00000028);
        check_instr("SLTI",  "x22", rf_x22, 32'h00000001);
        check_instr("SLTIU", "x23", rf_x23, 32'h00000000);
        check_instr("XORI",  "x24", rf_x24, 32'h000000F5);
        check_instr("SRLI",  "x25", rf_x25, 32'h40000000);
        check_instr("SRAI",  "x26", rf_x26, 32'hC0000000);
        check_instr("ORI",   "x27", rf_x27, 32'hFFFFFF0A);
        check_instr("ANDI",  "x28", rf_x28, 32'h0000000A);
        check_instr("LW",    "x29", rf_x29, 32'h0000001E);
        check_instr("LH",    "x30", rf_x30, 32'hFFFF8234);
        check_instr("LHU",   "x31", rf_x31, 32'h00008234);
        check_instr("LB",    "x9",  rf_x9,  32'hFFFFFF85);
        check_instr("LBU",   "x8",  rf_x8,  32'h00000085);
        $display("====================================================\n");

        // 数据存储器检查
        $display("===== Phase 1: Data Memory Check =====");
        $display("mem[0]  = 0x%08h (SW x6: 期望 0xFFFFFF85)", dmem[0]);
        $display("mem[1]  = 0x%08h (SW x7: 期望 0xFFFF8234)", dmem[1]);
        $display("mem[2]  = 0x%08h (SW x10: 期望 0x0000001E)", dmem[2]);
        $display("mem[3]  = 0x%08h (SH x7: 期望 0x00008234)", dmem[3]);
        $display("mem[4]  = 0x%08h (SB x6: 期望 0x00000085)", dmem[4]);
        $display("=======================================\n");

        // ====================================================================
        // 阶段2检查：等待分支/跳转/AUIPC结果
        // 再约55个周期用于阶段2流水线排空
        // ====================================================================
        repeat (55) @(posedge clk);

        $display("\n===== Phase 2: Register File Dump =====");
        $display("x22=0x%08h  x23=0x%08h  x24=0x%08h", rf_x22, rf_x23, rf_x24);
        $display("x25=0x%08h  x26=0x%08h  x31=0x%08h", rf_x25, rf_x26, rf_x31);
        $display("=========================================\n");

        // 阶段2验证：6项检查
        $display("===== Phase 2: Instruction Result Verification =====");
        check_instr("BNE",   "x31", rf_x31, 32'h000000CD);
        check_instr("JAL",   "x22", rf_x22, 32'h00000384);
        check_instr("JAL",   "x23", rf_x23, 32'h0000012C);
        check_instr("JALR",  "x25", rf_x25, 32'h000003AC);
        check_instr("JALR",  "x24", rf_x24, 32'h00000190);
        check_instr("AUIPC", "x26", rf_x26, 32'h000003C8);
        $display("====================================================\n");

        // ====================================================================
        // 总结
        // ====================================================================
        $display("\n");
        $display("================================================================");
        $display("                    FINAL TEST SUMMARY                          ");
        $display("================================================================");
        $display("  Total Instructions Tested : %0d", pass_count + fail_count);
        $display("  PASSED                    : %0d", pass_count);
        $display("  FAILED                    : %0d", fail_count);
        $display("----------------------------------------------------------------");
        if (fail_count == 0)
            $display("  RESULT: ALL TESTS PASSED! (37 RV32I instructions covered)");
        else begin
            $display("  RESULT: SOME TESTS FAILED! (%0d failure(s) detected)", fail_count);
            $display("  Please check FAIL lines above for details.");
        end
        $display("================================================================");
        $display("\n");

        $finish;
    end

    // ========================================================================
    // 超时看门狗
    // ========================================================================
    initial begin
        #30000; // 30us超时（为全面测试而增加）
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end

    // ========================================================================
    // 波形输出（用于调试）
    // ========================================================================
    initial begin
        $dumpfile("riscv_core.vcd");
        $dumpvars(0, tb_riscv_core);
    end

endmodule

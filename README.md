# RISC-V 双发射超标量处理器

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Vivado%2FXilinx%20FPGA-orange.svg)]()
[![Language](https://img.shields.io/badge/language-SystemVerilog-green.svg)]()
[![ISA](https://img.shields.io/badge/ISA-RV32I-red.svg)]()

基于 SystemVerilog 实现的 **RV32I 双发射超标量处理器**，5 级流水线，支持动态分支预测、数据前推与全方位冒险处理，适用于 Vivado/Xilinx FPGA 综合与仿真。

---

## 核心特性

| 特性 | 描述 |
|------|------|
| **指令集** | 全覆盖 RV32I（37 条指令） |
| **发射宽度** | 双发射超标量，双通道并行执行 |
| **流水线** | 5 级：IF → ID → EX → MEM → WB |
| **分支预测** | 动态 BTB + BHT + RAS，128 条目 2-way 组相连，8 深度返回地址栈 |
| **数据前推** | EX/MEM → EX 与 MEM/WB → EX 双路径前推 |
| **数据存储器** | 双端口哈佛架构，双通道独立访存 |
| **寄存器堆** | 32×32 位，4 读端口 + 2 写端口 |
| **测试平台** | 全覆盖 37 条 RV32I 指令，逐条输出 PASS/FAIL |

---

## 架构设计

### 流水线结构

```
  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
  │    IF    │───→│    ID    │───→│    EX    │───→│   MEM    │───→│    WB    │
  │  (取指)  │    │  (译码)  │    │  (执行)  │    │  (访存)  │    │  (写回)  │
  └──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
       │               │               │               │               │
  IF/ID寄存器      ID/EX寄存器      EX/MEM寄存器     MEM/WB寄存器      寄存器堆
   (双通道)         (双通道)         (双通道)          (双通道)        (4R2W)
```

### 双发射约束

- **通道 0（Lane 0）**：可执行所有指令类型
- **通道 1（Lane 1）**：支持 ALU 运算与访存指令（双端口存储器）
- 当 Lane 0 为**条件分支**指令时，Lane 1 自动插入气泡
- JAL/JALR 不阻塞 Lane 1（译码级即可确定，无控制流不确定性）
- 双通道同时访存时，硬件自动检测地址冲突

---

## 模块说明

| 模块 | 文件 | 功能 |
|------|------|------|
| `riscv_core` | [riscv_core.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/riscv_core.sv) | 顶层 CPU 核心，集成所有流水级和总线互联 |
| `fetch_unit` | [fetch_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/fetch_unit.sv) | 取指单元，64 位指令读取，PC 管理，分支预测接口 |
| `decode_unit` | [decode_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/decode_unit.sv) | 双通道译码，立即数生成，控制信号产生 |
| `execute_unit` | [execute_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/execute_unit.sv) | 双 ALU 执行，数据前推网络，分支解析 |
| `memory_unit` | [memory_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/memory_unit.sv) | 访存单元，支持 LB/LH/LW/LBU/LHU/SB/SH/SW |
| `writeback_unit` | [writeback_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/writeback_unit.sv) | 写回单元，双写端口寄存器写入 |
| `alu` | [alu.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/alu.sv) | 32 位 ALU：算术/逻辑/移位/比较 |
| `regfile` | [regfile.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/regfile.sv) | 32×32 寄存器堆，x0 硬连线为 0 |
| `branch_predictor` | [branch_predictor.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/branch_predictor.sv) | 动态分支预测器：BTB + BHT + RAS + LRU |
| `hazard_unit` | [hazard_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/hazard_unit.sv) | 冒险检测与流水线停顿/刷新控制 |
| `defines` | [defines.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/defines.sv) | RV32I 操作码 / funct3 / funct7 宏定义 |
| `types` | [types.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/types.sv) | 流水线寄存器结构体定义 |
| `tb_riscv_core` | [tb_riscv_core.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/tb_riscv_core.sv) | 完整 RV32I 测试平台，逐条指令输出 PASS/FAIL |

---

## 分支预测器

| 组件 | 规格 |
|------|------|
| **BTB** | 128 条目，2-way 组相连（64 组 × 2 路），PC[7:2] 索引，PC[13:8] 标签 |
| **BHT** | 每条目 2 位饱和计数器：`00`(强不跳) → `01`(弱不跳) → `10`(弱跳) → `11`(强跳) |
| **RAS** | 8 深度返回地址栈，JAL 压栈（推测执行），JALR 弹栈并预测返回地址 |
| **替换策略** | 组内伪 LRU 替换 |
| **优先级** | RAS 返回 > JAL 直接计算 > BTB 预测 > 顺序执行 |

---

## 冒险处理

| 冒险类型 | 处理方式 |
|----------|----------|
| **RAW 数据冒险** | EX/MEM → EX 与 MEM/WB → EX 前推网络，零停顿代价 |
| **Load-Use 冒险** | MEM/WB → EX 前推提供数据，无需额外停顿 |
| **控制冒险** | 分支预测错误时刷新 IF/ID、ID/EX，从正确地址重新取指 |
| **结构冒险（写端口）** | 双通道写同一寄存器时，译码级 Lane 1 失效 |
| **结构冒险（存储器）** | 双端口存储器支持并行访存；同地址冲突时 Lane 1 停顿 |

---

## 指令集（RV32I）

| 类别 | 指令 |
|------|------|
| **R-type ALU** | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| **I-type ALU** | ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI |
| **Load** | LB, LH, LW, LBU, LHU |
| **Store** | SB, SH, SW |
| **Branch** | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| **Jump** | JAL, JALR |
| **Upper Imm** | LUI, AUIPC |
| **系统** | FENCE, ECALL, EBREAK（译码为 NOP） |

---

## 测试平台

测试平台 `tb_riscv_core` 覆盖全部 37 条 RV32I 指令，分两阶段验证：

- **阶段 1**（31 项检查）：R-type ALU、I-type ALU、Store、Load
- **阶段 2**（6 项检查）：Branch、Jump、AUIPC

两阶段之间插入 30 条 NOP 对作为流水线排空间隔。每条指令独立验证，输出**明确的 PASS/FAIL**，包含指令助记符、寄存器名、实际值与期望值。

仿真输出示例：

```
===== Phase 1: Instruction Result Verification =====
[  1000]  PASS: ADDI   | x1 = 0x0000000a
[  1000]  PASS: ADD    | x10 = 0x0000001e
[  1000]  PASS: LW     | x29 = 0x0000001e
[  1000] *FAIL: SLL    | x12 = 0x00000000 (EXPECTED 0x000000a0)
...
================================================================
                    FINAL TEST SUMMARY
================================================================
  Total Instructions Tested : 37
  PASSED                    : 36
  FAILED                    : 1
----------------------------------------------------------------
  RESULT: SOME TESTS FAILED! (1 failure(s) detected)
================================================================
```

---

## 项目结构

```
RISC_V_CPU/
├── RISC_V_CPU.xpr                              # Vivado 工程文件
├── README.md                                   # 本文件
├── .gitignore                                  # Git 忽略规则
└── RISC_V_CPU.srcs/sources_1/imports/rtl/
    ├── defines.sv                              # 指令编码宏定义
    ├── types.sv                                # 流水线寄存器结构体定义
    ├── riscv_core.sv                           # 顶层 CPU 核心
    ├── fetch_unit.sv                           # 取指单元
    ├── decode_unit.sv                          # 双通道译码单元
    ├── execute_unit.sv                         # 双 ALU 执行单元
    ├── memory_unit.sv                          # 访存单元
    ├── writeback_unit.sv                       # 写回单元
    ├── alu.sv                                  # 算术逻辑单元
    ├── regfile.sv                              # 寄存器堆（32×32）
    ├── branch_predictor.sv                     # 分支预测器（BTB+BHT+RAS）
    ├── hazard_unit.sv                          # 冒险检测与流水线控制
    └── tb_riscv_core.sv                        # 完整 RV32I 测试平台
```

---

## 快速开始

### 环境要求

- **Vivado** 2023.2 或更高版本
- SystemVerilog 仿真器（XSim，Vivado 自带）

### 运行仿真

```bash
# 在 Vivado GUI 中打开工程
vivado RISC_V_CPU.xpr

# 或从命令行运行仿真
vivado -mode batch -source RISC_V_CPU.sim/sim_1/behav/xsim/tb_riscv_core.tcl
```

### 综合与实现

```bash
vivado -mode batch -source RISC_V_CPU.runs/impl_1/riscv_core.tcl
```

---

## 许可证

本项目仅供学习用途，欢迎自由使用、修改和研究。

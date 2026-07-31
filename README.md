# RISC-V Dual-Issue Superscalar Processor

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Vivado%2FXilinx%20FPGA-orange.svg)]()
[![Language](https://img.shields.io/badge/language-SystemVerilog-green.svg)]()
[![ISA](https://img.shields.io/badge/ISA-RV32I-red.svg)]()

A **dual-issue, 5-stage pipelined RV32I processor** implemented in SystemVerilog, featuring dynamic branch prediction, data forwarding, and comprehensive hazard handling. Designed for Vivado/Xilinx FPGA synthesis and simulation.

**基于 SystemVerilog 实现的 RV32I 双发射超标量处理器**，5 级流水线，支持动态分支预测与全方位冒险处理，面向 Vivado/Xilinx FPGA 综合与仿真。

---

## Features

| Feature | Description |
|---------|-------------|
| **ISA** | Full RV32I (37 instructions) |
| **Issue Width** | Dual-issue superscalar, two parallel lanes |
| **Pipeline** | 5 stages: IF -> ID -> EX -> MEM -> WB |
| **Branch Predictor** | Dynamic BTB + BHT + RAS, 128-entry 2-way set-associative, 8-depth return address stack |
| **Data Forwarding** | EX/MEM -> EX and MEM/WB -> EX dual-path forwarding |
| **Data Memory** | Dual-port Harvard architecture, independent access per lane |
| **Register File** | 32 x 32-bit, 4 read ports + 2 write ports |
| **Testbench** | Full coverage of all 37 RV32I instructions with per-instruction pass/fail reporting |

---

## Architecture

### Pipeline Overview

```
  +----------+     +----------+     +----------+     +----------+     +----------+
  |    IF    |---->|    ID    |---->|    EX    |---->|   MEM    |---->|    WB    |
  | (Fetch)  |     | (Decode) |     | (Execute)|     | (Memory) |     |(Writeback)|
  +----------+     +----------+     +----------+     +----------+     +----------+
       |                |                |                |                |
  IF/ID_REG        ID/EX_REG        EX/MEM_REG       MEM/WB_REG       RegFile
  (dual-lane)      (dual-lane)      (dual-lane)      (dual-lane)      (4R2W)
```

### Dual-Issue Constraints

- **Lane 0**: Can execute all instruction types
- **Lane 1**: Supports ALU operations and memory access (dual-port memory)
- When Lane 0 issues a **conditional branch**, Lane 1 is automatically bubbled
- JAL/JALR do NOT block Lane 1 (no control flow uncertainty in decode)
- Dual-lane concurrent memory access with hardware address conflict detection

---

## Module Structure

| Module | File | Description |
|--------|------|-------------|
| `riscv_core` | [riscv_core.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/riscv_core.sv) | Top-level CPU core, integrates all pipeline stages and bus interconnect |
| `fetch_unit` | [fetch_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/fetch_unit.sv) | Instruction fetch (64-bit), PC management, branch prediction interface |
| `decode_unit` | [decode_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/decode_unit.sv) | Dual-lane decode, immediate generation, control signal production |
| `execute_unit` | [execute_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/execute_unit.sv) | Dual ALU execution, data forwarding network, branch resolution |
| `memory_unit` | [memory_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/memory_unit.sv) | Memory access unit: LB/LH/LW/LBU/LHU/SB/SH/SW |
| `writeback_unit` | [writeback_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/writeback_unit.sv) | Writeback unit, dual write-port register write |
| `alu` | [alu.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/alu.sv) | 32-bit ALU: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU |
| `regfile` | [regfile.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/regfile.sv) | 32x32 register file, x0 hard-wired to 0 |
| `branch_predictor` | [branch_predictor.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/branch_predictor.sv) | Dynamic branch predictor: BTB + BHT + RAS + LRU |
| `hazard_unit` | [hazard_unit.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/hazard_unit.sv) | Hazard detection and pipeline stall/flush control |
| `defines` | [defines.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/defines.sv) | RV32I opcode / funct3 / funct7 macro definitions |
| `types` | [types.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/types.sv) | Pipeline register struct definitions |
| `tb_riscv_core` | [tb_riscv_core.sv](RISC_V_CPU.srcs/sources_1/imports/rtl/tb_riscv_core.sv) | Full RV32I testbench with per-instruction PASS/FAIL reporting |

---

## Branch Predictor

| Component | Specification |
|-----------|--------------|
| **BTB** | 128 entries, 2-way set-associative (64 sets x 2 ways), PC[7:2] index, PC[13:8] tag |
| **BHT** | 2-bit saturating counter per entry: `00`(strong not-taken) -> `01`(weak not-taken) -> `10`(weak taken) -> `11`(strong taken) |
| **RAS** | 8-deep return address stack, JAL pushes (speculative), JALR pops and predicts return |
| **Replacement** | Pseudo-LRU within each 2-way set |
| **Priority** | RAS return > JAL direct calc > BTB prediction > sequential |

---

## Hazard Handling

| Hazard | Resolution |
|--------|-----------|
| **RAW (Data)** | EX/MEM -> EX and MEM/WB -> EX forwarding network, zero stall penalty |
| **Load-Use** | MEM/WB -> EX forwarding provides data, no extra stall needed |
| **Control** | Flush IF/ID and ID/EX on branch mispredict, re-fetch from correct address |
| **Structural (Write Port)** | Lane 1 decode invalidated when both lanes target same register |
| **Structural (Memory)** | Dual-port memory supports parallel access; Lane 1 stalled on same-address conflict |

---

## Instruction Set (RV32I)

| Category | Instructions |
|----------|-------------|
| **R-type ALU** | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| **I-type ALU** | ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI |
| **Load** | LB, LH, LW, LBU, LHU |
| **Store** | SB, SH, SW |
| **Branch** | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| **Jump** | JAL, JALR |
| **Upper Imm** | LUI, AUIPC |
| **System** | FENCE, ECALL, EBREAK (decoded as NOP) |

---

## Testbench

The testbench `tb_riscv_core` covers all 37 RV32I instructions in **two phases**:

- **Phase 1** (31 checks): R-type ALU, I-type ALU, Store, Load
- **Phase 2** (6 checks): Branch, Jump, AUIPC

A 30-entry NOP gap between phases ensures pipeline drain. Each instruction is verified independently with **clear PASS/FAIL output**, showing the instruction mnemonic, register, and actual vs. expected values.

Example simulation output:

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

## Project Structure

```
RISC_V_CPU/
├── RISC_V_CPU.xpr                              # Vivado project file
├── README.md                                   # This file
├── .gitignore                                  # Git ignore rules
└── RISC_V_CPU.srcs/sources_1/imports/rtl/
    ├── defines.sv                              # Instruction encoding macros
    ├── types.sv                                # Pipeline register struct definitions
    ├── riscv_core.sv                           # Top-level CPU core
    ├── fetch_unit.sv                           # Instruction fetch unit
    ├── decode_unit.sv                          # Dual-lane decode unit
    ├── execute_unit.sv                         # Dual-ALU execution unit
    ├── memory_unit.sv                          # Memory access unit
    ├── writeback_unit.sv                       # Writeback unit
    ├── alu.sv                                  # Arithmetic Logic Unit
    ├── regfile.sv                              # Register file (32x32)
    ├── branch_predictor.sv                     # Branch predictor (BTB+BHT+RAS)
    ├── hazard_unit.sv                          # Hazard detection & pipeline control
    └── tb_riscv_core.sv                        # Full RV32I testbench
```

---

## Getting Started

### Prerequisites

- **Vivado** 2023.2 or later
- SystemVerilog simulator (XSim, included with Vivado)

### Run Simulation

```bash
# Open project in Vivado GUI
vivado RISC_V_CPU.xpr

# Or run simulation from command line
vivado -mode batch -source RISC_V_CPU.sim/sim_1/behav/xsim/tb_riscv_core.tcl
```

### Synthesis & Implementation

```bash
vivado -mode batch -source RISC_V_CPU.runs/impl_1/riscv_core.tcl
```

---

## License

This project is for educational purposes. Feel free to use, modify, and learn from it.

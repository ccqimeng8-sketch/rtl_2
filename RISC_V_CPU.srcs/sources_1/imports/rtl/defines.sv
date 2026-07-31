// ============================================================================
// Module : defines.sv
// Project: RISC-V 2-Issue Superscalar Processor
// Description: Global macro definitions, opcode encodings for RV32I ISA
// ============================================================================

`ifndef DEFINES_SV
`define DEFINES_SV

// ----------------------------------------------------------------------------
// RV32I Opcode Encodings (inst[6:0])
// ----------------------------------------------------------------------------
`define OPCODE_LUI      7'b0110111  // Load Upper Immediate (U-type)
`define OPCODE_AUIPC    7'b0010111  // Add Upper Immediate to PC (U-type)
`define OPCODE_JAL      7'b1101111  // Jump and Link (J-type)
`define OPCODE_JALR     7'b1100111  // Jump and Link Register (I-type)
`define OPCODE_BRANCH   7'b1100011  // Branch instructions (B-type)
`define OPCODE_LOAD     7'b0000011  // Load instructions (I-type)
`define OPCODE_STORE    7'b0100011  // Store instructions (S-type)
`define OPCODE_ALU_IMM  7'b0010011  // ALU immediate operations (I-type)
`define OPCODE_ALU      7'b0110011  // ALU register operations (R-type)
`define OPCODE_FENCE    7'b0001111  // Memory ordering fence (I-type)

// ----------------------------------------------------------------------------
// Funct3 Encodings for Branch Instructions
// ----------------------------------------------------------------------------
`define FUNCT3_BEQ      3'b000
`define FUNCT3_BNE      3'b001
`define FUNCT3_BLT      3'b100
`define FUNCT3_BGE      3'b101
`define FUNCT3_BLTU     3'b110
`define FUNCT3_BGEU     3'b111

// ----------------------------------------------------------------------------
// Funct3 Encodings for Load Instructions
// ----------------------------------------------------------------------------
`define FUNCT3_LB       3'b000
`define FUNCT3_LH       3'b001
`define FUNCT3_LW       3'b010
`define FUNCT3_LBU      3'b100
`define FUNCT3_LHU      3'b101

// ----------------------------------------------------------------------------
// Funct3 Encodings for Store Instructions
// ----------------------------------------------------------------------------
`define FUNCT3_SB       3'b000
`define FUNCT3_SH       3'b001
`define FUNCT3_SW       3'b010

// ----------------------------------------------------------------------------
// Funct3 Encodings for ALU Immediate / Register Instructions
// ----------------------------------------------------------------------------
`define FUNCT3_ADD_SUB  3'b000
`define FUNCT3_SLL      3'b001
`define FUNCT3_SLT      3'b010
`define FUNCT3_SLTU     3'b011
`define FUNCT3_XOR      3'b100
`define FUNCT3_SRL_SRA  3'b101
`define FUNCT3_OR       3'b110
`define FUNCT3_AND      3'b111

// ----------------------------------------------------------------------------
// Funct7 Discriminators for R-type Instructions
// ----------------------------------------------------------------------------
`define FUNCT7_NORMAL   7'b0000000  // Normal operations (ADD, SLL, etc.)
`define FUNCT7_ALT      7'b0100000  // Alternate operations (SUB, SRA)

// ----------------------------------------------------------------------------
// ALU Operation Codes (3-bit)
// ----------------------------------------------------------------------------
`define ALU_OP_ADD      3'b000
`define ALU_OP_SUB      3'b001
`define ALU_OP_AND      3'b010
`define ALU_OP_OR       3'b011
`define ALU_OP_XOR      3'b100
`define ALU_OP_SLL      3'b101
`define ALU_OP_SRL      3'b110
`define ALU_OP_SRA      3'b111

// ----------------------------------------------------------------------------
// Memory Access Width (funct3 low 2 bits)
// ----------------------------------------------------------------------------
`define MEM_WIDTH_BYTE   2'b00
`define MEM_WIDTH_HALF   2'b01
`define MEM_WIDTH_WORD   2'b10

// ----------------------------------------------------------------------------
// Branch Predictor Parameters (Optimized)
// ----------------------------------------------------------------------------
// BTB: 128 entries, 2-way set associative
//   - 64 sets × 2 ways = 128 entries
//   - Index: PC[7:2] (6 bits for 64 sets)
//   - Tag:   PC[13:8] (6 bits)
`define BTB_ENTRIES      128        // Total BTB entries (2-way × 64 sets)
`define BTB_WAYS         2          // 2-way set associative
`define BTB_SETS         64         // Number of sets
`define BTB_INDEX_BITS   6          // log2(64) = 6 bits index
`define BTB_TAG_BITS     6          // 6-bit tag
`define BHT_COUNTER_BITS 2          // 2-bit saturating counter

// RAS (Return Address Stack)
`define RAS_DEPTH        8          // 8-entry RAS for function returns

// ----------------------------------------------------------------------------
// Pipeline Control Signals
// ----------------------------------------------------------------------------
`define PC_RESET_VALUE   32'h0000_0000

`endif // DEFINES_SV

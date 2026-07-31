// ============================================================================
// Module : types.sv
// Project: RISC-V 2-Issue Superscalar Processor
// Description: Common type definitions - pipeline register structs, enums
// ============================================================================

`ifndef TYPES_SV
`define TYPES_SV

// ----------------------------------------------------------------------------
// IF/ID Pipeline Register
// Carries 2 fetched instructions + branch prediction info
// ----------------------------------------------------------------------------
typedef struct packed {
    // Lane 0
    logic [31:0] pc0;           // PC value for Lane 0
    logic [31:0] inst0;         // Instruction word for Lane 0
    logic        valid0;        // Lane 0 valid flag

    // Lane 1
    logic [31:0] pc1;           // PC value for Lane 1
    logic [31:0] inst1;         // Instruction word for Lane 1
    logic        valid1;        // Lane 1 valid flag

    // Branch prediction info (for Lane 0 only, as branches must be in Lane 0)
    logic        bp_taken0;     // Branch predicted taken
    logic [31:0] bp_target0;    // Predicted branch target address
} if_id_reg_t;

// ----------------------------------------------------------------------------
// ID/EX Pipeline Register
// Carries decoded control signals + register data for 2 lanes
// ----------------------------------------------------------------------------
typedef struct packed {
    // ===== Lane 0 =====
    logic [31:0] pc0;           // PC of Lane 0 instruction
    logic [4:0]  rd_addr0;      // Destination register address
    logic [31:0] rs1_data0;     // Source register 1 data (from regfile)
    logic [31:0] rs2_data0;     // Source register 2 data (from regfile)
    logic [31:0] imm0;          // Decoded immediate value
    logic [2:0]  alu_op0;       // ALU operation code
    logic        alu_src0;      // ALU source: 0=rs2, 1=imm
    logic        reg_write0;    // Register write enable
    logic        mem_read0;     // Memory read enable (Load)
    logic        mem_write0;    // Memory write enable (Store)
    logic [2:0]  mem_width0;    // Memory access width (B/H/W)
    logic        mem_sign0;     // Memory sign extension flag
    logic        branch0;       // Branch instruction flag
    logic        jump0;         // Jump instruction flag
    logic        auipc0;        // AUIPC instruction flag
    logic        lui0;          // LUI instruction flag
    logic [2:0]  funct3_0;      // funct3 for branch condition evaluation
    logic [4:0]  rs1_addr0;     // Source reg 1 addr (for forwarding compare)
    logic [4:0]  rs2_addr0;     // Source reg 2 addr (for forwarding compare)
    logic        valid0;        // Lane 0 valid flag

    // ===== Lane 1 =====
    logic [31:0] pc1;
    logic [4:0]  rd_addr1;
    logic [31:0] rs1_data1;
    logic [31:0] rs2_data1;
    logic [31:0] imm1;
    logic [2:0]  alu_op1;
    logic        alu_src1;
    logic        reg_write1;
    logic        mem_read1;
    logic        mem_write1;
    logic [2:0]  mem_width1;
    logic        mem_sign1;
    logic        branch1;
    logic        jump1;
    logic        auipc1;        // AUIPC instruction flag
    logic        lui1;          // LUI instruction flag
    logic [2:0]  funct3_1;
    logic [4:0]  rs1_addr1;
    logic [4:0]  rs2_addr1;
    logic        valid1;

    // Branch prediction info (for BTB/BHT update)
    logic        bp_taken0;     // Was branch predicted taken?
    logic [31:0] bp_target0;    // Predicted target address
} id_ex_reg_t;

// ----------------------------------------------------------------------------
// EX/MEM Pipeline Register
// Carries ALU results + memory control for 2 lanes
// ----------------------------------------------------------------------------
typedef struct packed {
    // ===== Lane 0 =====
    logic [31:0] alu_result0;   // ALU computation result
    logic [31:0] rs2_data0;     // Store data (rs2 value, forwarded)
    logic [4:0]  rd_addr0;      // Destination register address
    logic        reg_write0;    // Register write enable
    logic        mem_read0;     // Memory read enable
    logic        mem_write0;    // Memory write enable
    logic [2:0]  mem_width0;    // Memory access width
    logic        mem_sign0;     // Sign extension flag
    logic        branch_taken0; // Actual branch taken result
    logic [31:0] branch_target0;// Computed branch target
    logic        valid0;

    // ===== Lane 1 =====
    logic [31:0] alu_result1;
    logic [31:0] rs2_data1;
    logic [4:0]  rd_addr1;
    logic        reg_write1;
    logic        mem_read1;
    logic        mem_write1;
    logic [2:0]  mem_width1;
    logic        mem_sign1;
    logic        branch_taken1;
    logic [31:0] branch_target1;
    logic        valid1;
} ex_mem_reg_t;

// ----------------------------------------------------------------------------
// MEM/WB Pipeline Register
// Carries final write-back data for 2 lanes
// ----------------------------------------------------------------------------
typedef struct packed {
    // ===== Lane 0 =====
    logic [31:0] write_data0;   // Final data to write (ALU result or Load data)
    logic [4:0]  rd_addr0;      // Destination register address
    logic        reg_write0;    // Register write enable
    logic        valid0;        // Lane 0 valid flag

    // ===== Lane 1 =====
    logic [31:0] write_data1;
    logic [4:0]  rd_addr1;
    logic        reg_write1;
    logic        valid1;
} mem_wb_reg_t;

`endif // TYPES_SV

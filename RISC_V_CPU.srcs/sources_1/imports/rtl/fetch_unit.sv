// ============================================================================
// Module : fetch_unit
// Project: RISC-V 2-Issue Superscalar Processor
// Description: Instruction fetch unit for 2-wide superscalar pipeline.
//              - Manages PC register with update priority:
//                1) Branch mispredict correction (highest)
//                2) BTB predicted taken
//                3) Sequential fetch (PC + 4)
//                4) Stall (hold PC)
//              - Reads 64-bit from instruction memory (2 instructions)
//              - Handles 8-byte aligned instruction extraction
//              - When PC[2]==1 (misaligned), only emits 1 valid instruction
// ============================================================================

`include "defines.sv"

module fetch_unit (
    input  logic        clk,                    // Clock
    input  logic        rst_n,                  // Synchronous reset, active low

    // ----- Instruction Memory Interface -----
    output logic [31:0] imem_addr,              // Instruction memory address (8-byte aligned)
    input  logic [63:0] imem_rdata,             // 64-bit instruction data

    // ----- Branch Predictor Interface -----
    output logic [31:0] bp_pc,                  // Current PC sent to predictor
    input  logic        bp_hit,                 // BTB hit signal
    input  logic        bp_taken,               // Predict branch taken
    input  logic [31:0] bp_target,              // Predicted target address

    // ----- Pipeline Control Signals -----
    input  logic        stall,                  // Hold PC (don't advance)
    input  logic        flush,                  // Flush IF/ID register

    // ----- Branch Resolution (from Execute Stage) -----
    input  logic        branch_resolve,         // Branch has been resolved
    input  logic        branch_mispredict,      // Prediction was wrong
    input  logic [31:0] branch_correct_pc,      // Correct PC after resolution

    // ----- Outputs to IF/ID Pipeline Register -----
    output logic [31:0] fetch_pc0,              // Lane 0 PC
    output logic [31:0] fetch_pc1,              // Lane 1 PC
    output logic [31:0] fetch_inst0,            // Lane 0 instruction
    output logic [31:0] fetch_inst1,            // Lane 1 instruction
    output logic        fetch_valid0,           // Lane 0 valid
    output logic        fetch_valid1,           // Lane 1 valid
    output logic        fetch_bp_taken0,        // Lane 0 branch predicted taken
    output logic [31:0] fetch_bp_target0,       // Lane 0 predicted target

    // ----- Pre-decode Outputs (for Branch Predictor RAS) -----
    output logic        pre_is_jal,             // Lane 0 inst is JAL
    output logic        pre_is_jalr,            // Lane 0 inst is JALR
    output logic [31:0] pre_jal_target          // JAL target = PC + imm
);

    // ------------------------------------------------------------------------
    // PC Register
    // ------------------------------------------------------------------------
    logic [31:0] pc_reg;

    // ------------------------------------------------------------------------
    // Next PC Logic (Combinational)
    // Priority: mispredict > BTB taken > sequential
    // Sequential fetch always advances by 8 (2 instructions fetched per cycle)
    // ------------------------------------------------------------------------
    logic [31:0] pc_next;
    logic [31:0] seq_pc; // Sequential next PC

    // Always fetch 2 instructions (8 bytes), so PC always advances by 8
    assign seq_pc = pc_reg + 32'd8;

    always_comb begin
        if (branch_resolve && branch_mispredict) begin
            // Highest priority: correct branch misprediction
            pc_next = branch_correct_pc;
        end else if (bp_hit && bp_taken) begin
            // Second priority: BTB predicts taken -> jump to target
            pc_next = bp_target;
        end else begin
            // Default: sequential fetch
            pc_next = seq_pc;
        end
    end

    // ------------------------------------------------------------------------
    // PC Register Update (Synchronous)
    // - On reset: PC goes to reset vector
    // - On stall: hold current PC
    // - Otherwise: update to pc_next
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_reg <= `PC_RESET_VALUE;
        end else if (branch_resolve && branch_mispredict) begin
            // Branch correction always takes effect
            pc_reg <= branch_correct_pc;
        end else if (!stall) begin
            if (bp_hit && bp_taken)
                pc_reg <= bp_target;
            else
                pc_reg <= seq_pc;
        end
        // When stall is active, pc_reg holds its value
    end

    // ------------------------------------------------------------------------
    // Instruction Memory Address (8-byte aligned)
    // ------------------------------------------------------------------------
    assign imem_addr = {pc_reg[31:3], 3'b000};

    // ------------------------------------------------------------------------
    // Branch Predictor PC Input
    // ------------------------------------------------------------------------
    assign bp_pc = pc_reg;

    // ------------------------------------------------------------------------
    // Instruction Extraction (always 8-byte aligned, 2 instructions per fetch)
    // inst0 = rdata[31:0]   (lower 32 bits)
    // inst1 = rdata[63:32]  (upper 32 bits)
    // ------------------------------------------------------------------------

    // Lane 0 instruction and validity
    assign fetch_inst0  = imem_rdata[31:0];
    assign fetch_valid0 = 1'b1;  // Lane 0 always valid when fetching

    // Lane 1 instruction and validity
    assign fetch_inst1  = imem_rdata[63:32];
    assign fetch_valid1 = 1'b1;  // Lane 1 always valid (always 2 instructions)

    // ------------------------------------------------------------------------
    // PC Assignment to Lanes
    // ------------------------------------------------------------------------
    assign fetch_pc0 = pc_reg;
    assign fetch_pc1 = pc_reg + 32'd4;

    // ------------------------------------------------------------------------
    // Branch Prediction Info Output
    // - Only Lane 0 can be a branch (branches must be in Lane 0)
    // - Pass prediction result for later verification in EX stage
    // ------------------------------------------------------------------------
    assign fetch_bp_taken0  = bp_taken;
    assign fetch_bp_target0 = bp_target;

    // ------------------------------------------------------------------------
    // Pre-decode for Branch Predictor (RAS support)
    // Detect JAL/JALR in Lane 0 instruction for RAS prediction
    // ------------------------------------------------------------------------
    wire [6:0] inst0_opcode = imem_rdata[6:0];

    assign pre_is_jal  = (inst0_opcode == `OPCODE_JAL);
    assign pre_is_jalr = (inst0_opcode == `OPCODE_JALR);

    // JAL target = PC + J-type immediate
    // J-type: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
    assign pre_jal_target = pc_reg + {
        {11{imem_rdata[31]}},
        imem_rdata[31],
        imem_rdata[19:12],
        imem_rdata[20],
        imem_rdata[30:21],
        1'b0
    };

endmodule

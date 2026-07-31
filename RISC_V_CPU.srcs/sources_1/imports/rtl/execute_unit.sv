// ============================================================================
// Module : execute_unit
// Project: RISC-V 2-Issue Superscalar Processor
// Description: Dual-lane execute unit with 2 ALUs and forwarding network.
//              - Lane 0 ALU handles Lane 0 instructions
//              - Lane 1 ALU handles Lane 1 instructions
//              - Forwarding paths: EX/MEM -> EX, MEM/WB -> EX (both lanes)
//              - Branch condition evaluation in Lane 0
//              - Branch misprediction detection and correction
//              - BTB/BHT update signal generation
// ============================================================================

`include "defines.sv"
`include "types.sv"

module execute_unit (
    input  logic        clk,            // Clock
    input  logic        rst_n,          // Synchronous reset, active low

    // ----- Input from ID/EX Pipeline Register -----
    input  id_ex_reg_t  id_ex_in,       // Decoded instruction pair

    // ----- Forwarding Data from MEM/WB Stage -----
    input  logic [31:0] memwb_write_data0,  // MEM/WB Lane 0 write-back data
    input  logic [4:0]  memwb_rd_addr0,     // MEM/WB Lane 0 destination reg
    input  logic        memwb_reg_write0,   // MEM/WB Lane 0 register write en
    input  logic [31:0] memwb_write_data1,  // MEM/WB Lane 1 write-back data
    input  logic [4:0]  memwb_rd_addr1,     // MEM/WB Lane 1 destination reg
    input  logic        memwb_reg_write1,   // MEM/WB Lane 1 register write en

    // ----- Forwarding Data from EX/MEM Stage -----
    input  logic [31:0] exmem_alu_result0,  // EX/MEM Lane 0 ALU result
    input  logic [4:0]  exmem_rd_addr0,     // EX/MEM Lane 0 destination reg
    input  logic        exmem_reg_write0,   // EX/MEM Lane 0 register write en
    input  logic [31:0] exmem_alu_result1,  // EX/MEM Lane 1 ALU result
    input  logic [4:0]  exmem_rd_addr1,     // EX/MEM Lane 1 destination reg
    input  logic        exmem_reg_write1,   // EX/MEM Lane 1 register write en

    // ----- Output to EX/MEM Pipeline Register -----
    output ex_mem_reg_t ex_mem_out,

    // ----- Branch Resolution Signals -----
    output logic        branch_resolve,     // A branch was resolved this cycle
    output logic        branch_taken,       // Actual branch taken result
    output logic [31:0] branch_target,      // Computed branch target address
    output logic        branch_mispredict,  // Prediction was incorrect
    output logic [31:0] branch_correct_pc,  // Correct PC if mispredicted

    // ----- Branch Predictor Update Interface -----
    output logic        bp_update_valid,    // Update BTB/BHT
    output logic [31:0] bp_update_pc,       // Branch PC for update
    output logic        bp_update_taken,    // Actual taken outcome
    output logic [31:0] bp_update_target,   // Actual target address
    output logic [1:0]  bp_update_br_type   // 00=branch, 01=JAL, 10=JALR
);

    // ========================================================================
    // Forwarding Network
    // ========================================================================
    // For each ALU operand, select the most recent result from:
    //   Priority (low to high): Regfile -> MEM/WB -> EX/MEM

    // ----- Lane 0 Operand A Forwarding -----
    logic [31:0] fwd_a0;
    always_comb begin
        fwd_a0 = id_ex_in.rs1_data0; // Default: register file value

        // MEM/WB forwarding (lower priority)
        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs1_addr0))
            fwd_a0 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs1_addr0))
            fwd_a0 = memwb_write_data1;

        // EX/MEM forwarding (higher priority)
        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs1_addr0))
            fwd_a0 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs1_addr0))
            fwd_a0 = exmem_alu_result1;
    end

    // ----- Lane 0 Operand B Forwarding -----
    logic [31:0] fwd_b0;
    always_comb begin
        fwd_b0 = id_ex_in.rs2_data0;

        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs2_addr0))
            fwd_b0 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs2_addr0))
            fwd_b0 = memwb_write_data1;

        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs2_addr0))
            fwd_b0 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs2_addr0))
            fwd_b0 = exmem_alu_result1;
    end

    // ----- Lane 1 Operand A Forwarding -----
    logic [31:0] fwd_a1;
    always_comb begin
        fwd_a1 = id_ex_in.rs1_data1;

        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs1_addr1))
            fwd_a1 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs1_addr1))
            fwd_a1 = memwb_write_data1;

        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs1_addr1))
            fwd_a1 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs1_addr1))
            fwd_a1 = exmem_alu_result1;
    end

    // ----- Lane 1 Operand B Forwarding -----
    logic [31:0] fwd_b1;
    always_comb begin
        fwd_b1 = id_ex_in.rs2_data1;

        if (memwb_reg_write0 && (memwb_rd_addr0 != 5'b0) &&
            (memwb_rd_addr0 == id_ex_in.rs2_addr1))
            fwd_b1 = memwb_write_data0;
        if (memwb_reg_write1 && (memwb_rd_addr1 != 5'b0) &&
            (memwb_rd_addr1 == id_ex_in.rs2_addr1))
            fwd_b1 = memwb_write_data1;

        if (exmem_reg_write0 && (exmem_rd_addr0 != 5'b0) &&
            (exmem_rd_addr0 == id_ex_in.rs2_addr1))
            fwd_b1 = exmem_alu_result0;
        if (exmem_reg_write1 && (exmem_rd_addr1 != 5'b0) &&
            (exmem_rd_addr1 == id_ex_in.rs2_addr1))
            fwd_b1 = exmem_alu_result1;
    end

    // ========================================================================
    // ALU Input Selection
    // ========================================================================
    // op_a: always from forwarded rs1 (or PC for AUIPC/JAL)
    // op_b: forwarded rs2 or immediate (selected by alu_src)

    logic [31:0] alu_a0, alu_b0;
    logic [31:0] alu_a1, alu_b1;

    // Lane 0 ALU inputs
    always_comb begin
        // For AUIPC and JAL: op_a = PC
        // For JALR: op_a = rs1 (fwd_a0), NOT PC
        if (id_ex_in.auipc0 ||
            (id_ex_in.jump0 && (id_ex_in.alu_op0 == `ALU_OP_ADD) && !id_ex_in.alu_src0))
            alu_a0 = id_ex_in.pc0; // AUIPC/JAL: use PC
        else
            alu_a0 = fwd_a0;       // Normal: rs1 data (JALR also goes here)

        // For LUI: op_a = 0 (result = 0 + imm = imm)
        if (id_ex_in.lui0)
            alu_a0 = 32'b0;

        // op_b selection: immediate or forwarded rs2
        alu_b0 = id_ex_in.alu_src0 ? id_ex_in.imm0 : fwd_b0;
    end

    // Lane 1 ALU inputs
    always_comb begin
        alu_a1 = fwd_a1;

        if (id_ex_in.lui1)
            alu_a1 = 32'b0;        // LUI

        alu_b1 = id_ex_in.alu_src1 ? id_ex_in.imm1 : fwd_b1;
    end

    // ========================================================================
    // ALU Instances
    // ========================================================================

    logic [31:0] alu_result0, alu_result1;
    logic        alu_zero0, alu_zero1;
    logic        alu_less0, alu_less1;
    logic        alu_less_u0, alu_less_u1;

    alu u_alu0 (
        .op_a   (alu_a0),
        .op_b   (alu_b0),
        .alu_op (id_ex_in.alu_op0),
        .result (alu_result0),
        .zero   (alu_zero0),
        .less   (alu_less0),
        .less_u (alu_less_u0)
    );

    alu u_alu1 (
        .op_a   (alu_a1),
        .op_b   (alu_b1),
        .alu_op (id_ex_in.alu_op1),
        .result (alu_result1),
        .zero   (alu_zero1),
        .less   (alu_less1),
        .less_u (alu_less_u1)
    );

    // ========================================================================
    // Branch Condition Evaluation (Lane 0 only)
    // ========================================================================
    // Branch instructions compare rs1 and rs2 using the appropriate condition.
    // The comparison uses the forwarded operand values.

    logic        branch_taken_internal;
    logic [31:0] branch_target_calc;

    // Branch target = PC + immediate (for B-type instructions)
    assign branch_target_calc = id_ex_in.pc0 + id_ex_in.imm0;

    // Evaluate branch condition based on funct3
    always_comb begin
        branch_taken_internal = 1'b0;

        if (id_ex_in.branch0 && id_ex_in.valid0) begin
            case (id_ex_in.funct3_0)
                `FUNCT3_BEQ:  branch_taken_internal = alu_zero0;         // rs1 == rs2
                `FUNCT3_BNE:  branch_taken_internal = ~alu_zero0;        // rs1 != rs2
                `FUNCT3_BLT:  branch_taken_internal = alu_less0;         // rs1 < rs2 (signed)
                `FUNCT3_BGE:  branch_taken_internal = ~alu_less0;        // rs1 >= rs2 (signed)
                `FUNCT3_BLTU: branch_taken_internal = alu_less_u0;       // rs1 < rs2 (unsigned)
                `FUNCT3_BGEU: branch_taken_internal = ~alu_less_u0;      // rs1 >= rs2 (unsigned)
                default:      branch_taken_internal = 1'b0;
            endcase
        end
    end

    // ========================================================================
    // Branch Misprediction Detection
    // ========================================================================
    // Compare actual branch outcome with prediction from BTB/BHT.
    // Misprediction occurs when:
    //   1. Predicted taken but actually not taken (or vice versa)
    //   2. Predicted target address differs from actual target

    assign branch_resolve = id_ex_in.branch0 & id_ex_in.valid0;

    assign branch_taken = branch_taken_internal;
    assign branch_target = branch_target_calc;

    assign branch_mispredict = branch_resolve &
        ((branch_taken_internal != id_ex_in.bp_taken0) |
         (branch_taken_internal & (branch_target_calc != id_ex_in.bp_target0)));

    // Correct PC: branch target (if taken) or sequential next PC (if not taken)
    // Since we always fetch 2 instructions per cycle, the next sequential
    // instruction is always at PC+4 (Lane 1 of the same fetch pair)
    assign branch_correct_pc = branch_taken_internal ? branch_target_calc :
        (id_ex_in.pc0 + 32'd4);

    // ========================================================================
    // Branch Predictor Update Signals
    // ========================================================================
    // Update BTB/BHT whenever a branch instruction is resolved

    assign bp_update_valid  = (id_ex_in.branch0 | id_ex_in.jump0) & id_ex_in.valid0;
    assign bp_update_pc     = id_ex_in.pc0;
    assign bp_update_taken  = branch_taken_internal;
    assign bp_update_target = branch_target_calc;

    // Determine branch type: 00=conditional branch, 01=JAL(call), 10=JALR(ret)
    assign bp_update_br_type = id_ex_in.branch0 ? 2'b00 :
                               (id_ex_in.jump0 ? (id_ex_in.alu_src0 ? 2'b10 : 2'b01) : 2'b00);

    // ========================================================================
    // JALR Target Address Correction
    // ========================================================================
    // JALR: PC <= (rs1 + imm) & ~1
    // The ALU computes rs1 + imm; we need to clear bit 0.
    // This is handled by modifying the result for jump instructions.

    logic [31:0] final_result0, final_result1;

    // For JAL/JALR, ensure bit 0 of target is cleared
    assign final_result0 = id_ex_in.jump0 ?
        {alu_result0[31:1], 1'b0} : alu_result0;

    // Lane 1 doesn't have JALR (it's forced to bubble if Lane 0 jumps)
    assign final_result1 = alu_result1;

    // ========================================================================
    // SLT/SLTU Result Correction
    // ========================================================================
    // For SLT/SLTI: result = less ? 1 : 0
    // For SLTU/SLTIU: result = less_u ? 1 : 0
    // The ALU performs SUB; we override the result for these operations.

    logic [31:0] corrected_result0, corrected_result1;

    always_comb begin
        corrected_result0 = final_result0;

        if (id_ex_in.valid0) begin
            case ({id_ex_in.alu_op0, id_ex_in.funct3_0})
                // SLT / SLTI (R-type and I-type): funct3=010, alu_op=SUB
                {`ALU_OP_SUB, `FUNCT3_SLT}:
                    corrected_result0 = {31'b0, alu_less0};
                // SLTU / SLTIU (R-type and I-type): funct3=011, alu_op=SUB
                {`ALU_OP_SUB, `FUNCT3_SLTU}:
                    corrected_result0 = {31'b0, alu_less_u0};
                default: ; // No correction needed
            endcase
        end
    end

    always_comb begin
        corrected_result1 = final_result1;

        if (id_ex_in.valid1) begin
            case ({id_ex_in.alu_op1, id_ex_in.funct3_1})
                // SLT / SLTI (R-type and I-type)
                {`ALU_OP_SUB, `FUNCT3_SLT}:
                    corrected_result1 = {31'b0, alu_less1};
                // SLTU / SLTIU (R-type and I-type)
                {`ALU_OP_SUB, `FUNCT3_SLTU}:
                    corrected_result1 = {31'b0, alu_less_u1};
                default: ;
            endcase
        end
    end

    // ========================================================================
    // JAL rd Result: rd = PC + 4
    // ========================================================================
    // For JAL: the ALU computes PC + imm (for target), but rd needs PC + 4.
    // We override the result for JAL instructions.

    logic [31:0] jal_result0;
    assign jal_result0 = id_ex_in.jump0 ?
        (id_ex_in.pc0 + 32'd4) : corrected_result0; // JAL/JALR: rd = PC+4

    logic [31:0] jal_result1;
    assign jal_result1 = (id_ex_in.jump1 && !id_ex_in.alu_src1) ?
        (id_ex_in.pc1 + 32'd4) : corrected_result1;

    // ========================================================================
    // EX/MEM Output Assembly
    // ========================================================================
    always_comb begin
        // ===== Lane 0 =====
        ex_mem_out.alu_result0   = jal_result0;
        ex_mem_out.rs2_data0     = fwd_b0;       // Store data (forwarded rs2)
        ex_mem_out.rd_addr0      = id_ex_in.rd_addr0;
        ex_mem_out.reg_write0    = id_ex_in.reg_write0 & id_ex_in.valid0;
        ex_mem_out.mem_read0     = id_ex_in.mem_read0 & id_ex_in.valid0;
        ex_mem_out.mem_write0    = id_ex_in.mem_write0 & id_ex_in.valid0;
        ex_mem_out.mem_width0    = id_ex_in.mem_width0;
        ex_mem_out.mem_sign0     = id_ex_in.mem_sign0;
        ex_mem_out.branch_taken0 = branch_taken_internal;
        ex_mem_out.branch_target0= branch_target_calc;
        ex_mem_out.valid0        = id_ex_in.valid0;

        // ===== Lane 1 =====
        ex_mem_out.alu_result1   = jal_result1;
        ex_mem_out.rs2_data1     = fwd_b1;
        ex_mem_out.rd_addr1      = id_ex_in.rd_addr1;
        ex_mem_out.reg_write1    = id_ex_in.reg_write1 & id_ex_in.valid1;
        ex_mem_out.mem_read1     = id_ex_in.mem_read1 & id_ex_in.valid1;
        ex_mem_out.mem_write1    = id_ex_in.mem_write1 & id_ex_in.valid1;
        ex_mem_out.mem_width1    = id_ex_in.mem_width1;
        ex_mem_out.mem_sign1     = id_ex_in.mem_sign1;
        ex_mem_out.branch_taken1 = 1'b0; // Lane 1 cannot have branches
        ex_mem_out.branch_target1= 32'b0;
        ex_mem_out.valid1        = id_ex_in.valid1;
    end

endmodule

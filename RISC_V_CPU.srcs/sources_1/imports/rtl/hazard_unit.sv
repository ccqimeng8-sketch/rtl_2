// ============================================================================
// Module : hazard_unit
// Project: RISC-V 2-Issue Superscalar Processor (Optimized)
// Description: Hazard detection and pipeline control unit.
//              Detects the following hazards:
//              1. Structural hazard: register write conflict between lanes
//              2. Structural hazard: same-address memory access in both lanes
//              3. Control hazard: branch misprediction causes pipeline flush
//
//              NOTE: Load-Use hazard does NOT require a stall in this design.
//              When a Load is in MEM/WB stage, the dependent instruction is in
//              EX stage. The MEM/WB → EX forwarding network provides the correct
//              Load data combinationally, and the result is captured into EX/MEM
//              at the next clock edge. No stall needed.
//
//              NOTE: With dual-port data memory, both lanes can access memory
//              simultaneously. Same-address conflicts are detected here.
//
//              Generates stall, flush, and fetch_stall signals.
// ============================================================================

`include "defines.sv"
`include "types.sv"

module hazard_unit (
    // ----- ID Stage Instruction Info -----
    input  logic [4:0]  id_rd_addr0,        // Lane 0 destination register
    input  logic        id_reg_write0,      // Lane 0 will write register
    input  logic        id_valid0,          // Lane 0 valid
    input  logic [4:0]  id_rd_addr1,        // Lane 1 destination register
    input  logic        id_reg_write1,      // Lane 1 will write register
    input  logic        id_valid1,          // Lane 1 valid
    input  logic        id_mem_read0,       // Lane 0 is a Load instruction
    input  logic        id_mem_read1,       // Lane 1 is a Load instruction
    input  logic        id_mem_write0,      // Lane 0 is a Store instruction
    input  logic        id_mem_write1,      // Lane 1 is a Store instruction
    input  logic [4:0]  id_rs1_addr0,       // Lane 0 source register 1
    input  logic [4:0]  id_rs2_addr0,       // Lane 0 source register 2
    input  logic [4:0]  id_rs1_addr1,       // Lane 1 source register 1
    input  logic [4:0]  id_rs2_addr1,       // Lane 1 source register 2

    // ----- EX/MEM Stage Info -----
    input  logic [4:0]  exmem_rd_addr0,     // EX/MEM Lane 0 destination
    input  logic        exmem_reg_write0,   // EX/MEM Lane 0 writes register
    input  logic        exmem_mem_read0,    // EX/MEM Lane 0 is Load
    input  logic [4:0]  exmem_rd_addr1,     // EX/MEM Lane 1 destination
    input  logic        exmem_reg_write1,   // EX/MEM Lane 1 writes register

    // ----- MEM/WB Stage Info -----
    input  logic [4:0]  memwb_rd_addr0,     // MEM/WB Lane 0 destination
    input  logic        memwb_reg_write0,   // MEM/WB Lane 0 writes register
    input  logic [4:0]  memwb_rd_addr1,     // MEM/WB Lane 1 destination
    input  logic        memwb_reg_write1,   // MEM/WB Lane 1 writes register

    // ----- Branch Resolution Signals -----
    input  logic        branch_resolve,     // Branch instruction resolved in EX
    input  logic        branch_mispredict,  // Branch was mispredicted

    // ----- Output Control Signals -----
    output logic        stall,              // Pipeline stall (all stages hold)
    output logic        flush_if_id,        // Flush IF/ID pipeline register
    output logic        flush_id_ex,        // Flush ID/EX pipeline register
    output logic        stall_fetch          // Stall instruction fetch
);

    // ========================================================================
    // 1. Structural Hazard Detection
    // ========================================================================
    // Register write conflict: both lanes writing to the same register cannot
    // proceed simultaneously. The decode unit also handles this via the
    // eff_valid1 mechanism, but we keep this as a safety check.

    logic wr_struct_hazard;
    assign wr_struct_hazard = id_valid0 & id_valid1 &
        id_reg_write0 & id_reg_write1 &
        (id_rd_addr0 != 5'b0) & (id_rd_addr1 != 5'b0) &
        (id_rd_addr0 == id_rd_addr1);

    // ========================================================================
    // 2. Memory Address Conflict Detection (Dual-Port)
    // ========================================================================
    // When both lanes access data memory simultaneously, check for conflicts:
    //   - Same address + at least one write → structural hazard
    // Lane 0 has priority; Lane 1 is stalled.

    logic mem_conflict;

    // Compute Lane 0 and Lane 1 memory addresses from ID stage info
    // At ID stage, the address is rs1 + imm (pre-ALU). We approximate
    // by checking if both lanes have memory ops active.
    // Full address comparison happens at EX/MEM stage.
    // For now: detect if both lanes issue memory ops to potentially same region.
    // This is conservative: stall if both lanes have ANY memory op.

    // Conservative: if both lanes have memory ops (Load or Store), stall Lane 1.
    // This can be refined later with actual address comparison.
    logic dual_mem_op;
    assign dual_mem_op = (id_mem_read0 | id_mem_write0) &
                         (id_mem_read1 | id_mem_write1) &
                         id_valid0 & id_valid1;

    assign mem_conflict = dual_mem_op;

    // ========================================================================
    // 3. Control Hazard (Branch Misprediction)
    // ========================================================================
    // When a branch is resolved in EX stage and prediction was wrong,
    // flush the IF/ID and ID/EX pipeline registers.

    logic control_flush;
    assign control_flush = branch_resolve & branch_mispredict;

    // ========================================================================
    // Combined Output Signals
    // ========================================================================

    // Stall: asserted when structural hazard or memory conflict detected
    assign stall = wr_struct_hazard | mem_conflict;

    // Stall fetch: same as pipeline stall
    assign stall_fetch = stall;

    // Flush IF/ID: on branch misprediction (discard wrongly fetched instructions)
    assign flush_if_id = control_flush;

    // Flush ID/EX: on stall (insert bubble) or branch misprediction
    assign flush_id_ex = stall | control_flush;

endmodule

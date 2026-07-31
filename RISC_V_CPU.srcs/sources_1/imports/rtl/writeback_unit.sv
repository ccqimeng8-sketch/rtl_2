// ============================================================================
// Module : writeback_unit
// Project: RISC-V 2-Issue Superscalar Processor
// Description: Write-back unit that writes results to the register file.
//              - 2 write ports (Lane 0 and Lane 1)
//              - Lane 0 has priority; x0 writes are suppressed
//              - Write conflict (same rd in both lanes) is prevented by
//                the hazard unit stalling Lane 1 in decode stage
// ============================================================================

`include "defines.sv"
`include "types.sv"

module writeback_unit (
    input  logic        clk,            // Clock (unused, purely combinational)
    input  logic        rst_n,          // Synchronous reset (unused)

    // ----- Input from MEM/WB Pipeline Register -----
    input  mem_wb_reg_t mem_wb_in,      // Final write-back data for both lanes

    // ----- Register File Write Port 0 (Lane 0) -----
    output logic [4:0]  rf_waddr0,      // Write address for Lane 0
    output logic [31:0] rf_wdata0,      // Write data for Lane 0
    output logic        rf_we0,         // Write enable for Lane 0

    // ----- Register File Write Port 1 (Lane 1) -----
    output logic [4:0]  rf_waddr1,      // Write address for Lane 1
    output logic [31:0] rf_wdata1,      // Write data for Lane 1
    output logic        rf_we1          // Write enable for Lane 1
);

    // ========================================================================
    // Lane 0 Write-Back
    // ========================================================================
    // Write to register file when:
    //   - reg_write is asserted
    //   - Lane is valid
    //   - Destination is not x0 (x0 is hardwired to zero)

    assign rf_waddr0 = mem_wb_in.rd_addr0;
    assign rf_wdata0 = mem_wb_in.write_data0;
    assign rf_we0    = mem_wb_in.reg_write0 &
                       mem_wb_in.valid0 &
                       (mem_wb_in.rd_addr0 != 5'b0);

    // ========================================================================
    // Lane 1 Write-Back
    // ========================================================================
    // Same conditions as Lane 0.
    // Note: If both lanes write to the same register, the hazard unit
    // should have stalled Lane 1 in decode. As a safety measure,
    // the register file also checks for address conflicts.

    assign rf_waddr1 = mem_wb_in.rd_addr1;
    assign rf_wdata1 = mem_wb_in.write_data1;
    assign rf_we1    = mem_wb_in.reg_write1 &
                       mem_wb_in.valid1 &
                       (mem_wb_in.rd_addr1 != 5'b0);

endmodule

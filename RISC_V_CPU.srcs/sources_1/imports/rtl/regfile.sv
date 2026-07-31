// ============================================================================
// Module : regfile
// Project: RISC-V 2-Issue Superscalar Processor
// Description: 32x32-bit register file with 4 read ports and 2 write ports.
//              - Read Port 0: Lane 0 rs1
//              - Read Port 1: Lane 0 rs2
//              - Read Port 2: Lane 1 rs1
//              - Read Port 3: Lane 1 rs2
//              - Write Port 0: Lane 0 writeback
//              - Write Port 1: Lane 1 writeback
//              Register x0 is hardwired to zero.
//              Read is combinational, write is synchronous (posedge clk).
// ============================================================================

module regfile (
    input  logic        clk,        // Clock
    input  logic        rst_n,      // Synchronous reset, active low

    // ----- Read Port 0 (Lane 0 rs1) -----
    input  logic [4:0]  raddr0,     // Read address
    output logic [31:0] rdata0,     // Read data

    // ----- Read Port 1 (Lane 0 rs2) -----
    input  logic [4:0]  raddr1,     // Read address
    output logic [31:0] rdata1,     // Read data

    // ----- Read Port 2 (Lane 1 rs1) -----
    input  logic [4:0]  raddr2,     // Read address
    output logic [31:0] rdata2,     // Read data

    // ----- Read Port 3 (Lane 1 rs2) -----
    input  logic [4:0]  raddr3,     // Read address
    output logic [31:0] rdata3,     // Read data

    // ----- Write Port 0 (Lane 0 writeback) -----
    input  logic [4:0]  waddr0,     // Write address
    input  logic [31:0] wdata0,     // Write data
    input  logic        we0,        // Write enable

    // ----- Write Port 1 (Lane 1 writeback) -----
    input  logic [4:0]  waddr1,     // Write address
    input  logic [31:0] wdata1,     // Write data
    input  logic        we1         // Write enable
);

    // ------------------------------------------------------------------------
    // Register array: 32 x 32-bit general purpose registers
    // x0 is hardwired to zero (never written)
    // ------------------------------------------------------------------------
    logic [31:0] regs [0:31];

    // ------------------------------------------------------------------------
    // Read Logic (Combinational)
    // x0 always returns 0
    // ------------------------------------------------------------------------
    assign rdata0 = (raddr0 == 5'b0) ? 32'b0 : regs[raddr0];
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : regs[raddr2];
    assign rdata3 = (raddr3 == 5'b0) ? 32'b0 : regs[raddr3];

    // ------------------------------------------------------------------------
    // Write Logic (Synchronous with reset)
    // - Reset: all registers cleared to 0
    // - Only write to non-x0 registers when write enable is active
    // - Lane 0 has priority: if both lanes write to same address,
    //   Lane 1 should have been stalled in decode stage.
    //   Safety: Lane 1 write is suppressed if same address as Lane 0.
    // ------------------------------------------------------------------------
    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i++) begin
                regs[i] <= 32'b0;
            end
        end else begin
            // Write Port 0 (Lane 0) - higher priority
            if (we0 && (waddr0 != 5'b0)) begin
                regs[waddr0] <= wdata0;
            end

            // Write Port 1 (Lane 1) - lower priority
            if (we1 && (waddr1 != 5'b0) && !(we0 && (waddr1 == waddr0))) begin
                regs[waddr1] <= wdata1;
            end
        end
    end

endmodule

// ============================================================================
// Module : alu
// Project: RISC-V 2-Issue Superscalar Processor
// Description: 32-bit Arithmetic Logic Unit supporting 8 operations:
//              ADD, SUB, AND, OR, XOR, SLL, SRL, SRA.
//              Also outputs zero flag and signed/unsigned less-than flags.
//              Purely combinational logic, no sequential elements.
// ============================================================================

`include "defines.sv"

module alu (
    input  logic [31:0] op_a,       // Operand A (first input)
    input  logic [31:0] op_b,       // Operand B (second input)
    input  logic [2:0]  alu_op,     // ALU operation code

    output logic [31:0] result,     // Computation result
    output logic        zero,       // Result is zero flag
    output logic        less,       // Signed less-than (op_a < op_b)
    output logic        less_u      // Unsigned less-than (op_a < op_b)
);

    // ------------------------------------------------------------------------
    // Main ALU Computation (Combinational)
    // ------------------------------------------------------------------------
    always_comb begin
        case (alu_op)
            `ALU_OP_ADD: result = op_a + op_b;
            `ALU_OP_SUB: result = op_a - op_b;
            `ALU_OP_AND: result = op_a & op_b;
            `ALU_OP_OR:  result = op_a | op_b;
            `ALU_OP_XOR: result = op_a ^ op_b;
            `ALU_OP_SLL: result = op_a << op_b[4:0];       // Logical left shift
            `ALU_OP_SRL: result = op_a >> op_b[4:0];       // Logical right shift
            `ALU_OP_SRA: result = $signed(op_a) >>> op_b[4:0]; // Arithmetic right shift
            default:     result = 32'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Status Flags (Combinational)
    // ------------------------------------------------------------------------

    // Zero flag: asserted when result is all zeros
    assign zero = (result == 32'b0);

    // Signed less-than: compare operands as signed integers
    assign less = ($signed(op_a) < $signed(op_b));

    // Unsigned less-than: compare operands as unsigned integers
    assign less_u = (op_a < op_b);

endmodule

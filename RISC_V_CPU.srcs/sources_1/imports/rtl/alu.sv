// ============================================================================
// 模块 : alu
// 项目: RISC-V 双发射超标量处理器
// 描述: 32 位算术逻辑单元, 支持 8 种操作:
//       ADD, SUB, AND, OR, XOR, SLL, SRL, SRA.
//       同时输出零标志、有符号/无符号小于标志.
//       纯组合逻辑, 无时序元件.
// ============================================================================

`include "defines.sv"

module alu (
    input  logic [31:0] op_a,       // 操作数 A (第一个输入)
    input  logic [31:0] op_b,       // 操作数 B (第二个输入)
    input  logic [2:0]  alu_op,     // ALU 操作码

    output logic [31:0] result,     // 计算结果
    output logic        zero,       // 结果为零标志
    output logic        less,       // 有符号小于 (op_a < op_b)
    output logic        less_u      // 无符号小于 (op_a < op_b)
);

    // ------------------------------------------------------------------------
    // ALU 主计算 (组合逻辑)
    // ------------------------------------------------------------------------
    always_comb begin
        case (alu_op)
            `ALU_OP_ADD: result = op_a + op_b;
            `ALU_OP_SUB: result = op_a - op_b;
            `ALU_OP_AND: result = op_a & op_b;
            `ALU_OP_OR:  result = op_a | op_b;
            `ALU_OP_XOR: result = op_a ^ op_b;
            `ALU_OP_SLL: result = op_a << op_b[4:0];       // 逻辑左移
            `ALU_OP_SRL: result = op_a >> op_b[4:0];       // 逻辑右移
            `ALU_OP_SRA: result = $signed(op_a) >>> op_b[4:0]; // 算术右移
            default:     result = 32'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // 状态标志 (组合逻辑)
    // ------------------------------------------------------------------------

    // 零标志: 当结果全零时置位
    assign zero = (result == 32'b0);

    // 有符号小于: 将操作数作为有符号整数比较
    assign less = ($signed(op_a) < $signed(op_b));

    // 无符号小于: 将操作数作为无符号整数比较
    assign less_u = (op_a < op_b);

endmodule

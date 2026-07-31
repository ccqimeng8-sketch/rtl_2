// ============================================================================
// Module : memory_unit
// Project: RISC-V 2-Issue Superscalar Processor (Optimized)
// Description: Dual-lane memory access unit with dual-port data memory.
//              - Supports LB/LH/LW/LBU/LHU (Load) and SB/SH/SW (Store)
//              - Each lane has its own independent memory port
//              - Byte enable generation based on address and access width
//              - Store data alignment (rotate based on address offset)
//              - Load data alignment and sign/zero extension
//              - Dual-port: Lane 0 and Lane 1 access memory independently
// ============================================================================

`include "defines.sv"
`include "types.sv"

module memory_unit (
    input  logic        clk,            // Clock
    input  logic        rst_n,          // Synchronous reset, active low

    // ----- Input from EX/MEM Pipeline Register -----
    input  ex_mem_reg_t ex_mem_in,      // ALU results + control signals

    // ----- Data Memory Port 0 (Lane 0, 32-bit) -----
    output logic [31:0] dmem_addr0,     // Lane 0 memory address
    output logic [31:0] dmem_wdata0,    // Lane 0 write data (aligned)
    output logic        dmem_we0,       // Lane 0 write enable
    output logic [3:0]  dmem_be0,       // Lane 0 byte enable
    input  logic [31:0] dmem_rdata0,    // Lane 0 read data

    // ----- Data Memory Port 1 (Lane 1, 32-bit) -----
    output logic [31:0] dmem_addr1,     // Lane 1 memory address
    output logic [31:0] dmem_wdata1,    // Lane 1 write data (aligned)
    output logic        dmem_we1,       // Lane 1 write enable
    output logic [3:0]  dmem_be1,       // Lane 1 byte enable
    input  logic [31:0] dmem_rdata1,    // Lane 1 read data

    // ----- Output to MEM/WB Pipeline Register -----
    output mem_wb_reg_t mem_wb_out       // Write-back data for both lanes
);

    // ========================================================================
    // Lane 0 Memory Access Logic
    // ========================================================================

    // Address comes from ALU result (computed in EX stage)
    logic [31:0] addr0;
    assign addr0 = ex_mem_in.alu_result0;

    // Byte enable generation for Lane 0
    logic [3:0] be0;
    always_comb begin
        case (ex_mem_in.mem_width0[1:0])
            `MEM_WIDTH_BYTE: be0 = 4'b0001 << addr0[1:0]; // 1 byte
            `MEM_WIDTH_HALF: be0 = 4'b0011 << addr0[1:0]; // 2 bytes (halfword)
            `MEM_WIDTH_WORD: be0 = 4'b1111;                // 4 bytes (word)
            default:         be0 = 4'b0000;
        endcase
    end

    // Store data alignment for Lane 0
    logic [31:0] store_data0;
    always_comb begin
        case (addr0[1:0])
            2'b00: store_data0 = ex_mem_in.rs2_data0;
            2'b01: store_data0 = {ex_mem_in.rs2_data0[23:0], ex_mem_in.rs2_data0[31:24]};
            2'b10: store_data0 = {ex_mem_in.rs2_data0[15:0], ex_mem_in.rs2_data0[31:16]};
            2'b11: store_data0 = {ex_mem_in.rs2_data0[7:0],  ex_mem_in.rs2_data0[31:24]};
        endcase
    end

    // Load data alignment and sign/zero extension for Lane 0
    logic [31:0] load_data0;
    logic sign_ext0;
    assign sign_ext0 = ex_mem_in.mem_sign0; // 1 = sign extend, 0 = zero extend

    always_comb begin
        case (ex_mem_in.mem_width0[1:0])
            `MEM_WIDTH_BYTE: begin // Byte load
                case (addr0[1:0])
                    2'b00: load_data0 = {{24{sign_ext0 & dmem_rdata0[7]}},  dmem_rdata0[7:0]};
                    2'b01: load_data0 = {{24{sign_ext0 & dmem_rdata0[15]}}, dmem_rdata0[15:8]};
                    2'b10: load_data0 = {{24{sign_ext0 & dmem_rdata0[23]}}, dmem_rdata0[23:16]};
                    2'b11: load_data0 = {{24{sign_ext0 & dmem_rdata0[31]}}, dmem_rdata0[31:24]};
                endcase
            end
            `MEM_WIDTH_HALF: begin // Halfword load
                case (addr0[1])
                    1'b0: load_data0 = {{16{sign_ext0 & dmem_rdata0[15]}}, dmem_rdata0[15:0]};
                    1'b1: load_data0 = {{16{sign_ext0 & dmem_rdata0[31]}}, dmem_rdata0[31:16]};
                endcase
            end
            `MEM_WIDTH_WORD: begin // Word load
                load_data0 = dmem_rdata0;
            end
            default: begin
                load_data0 = 32'b0;
            end
        endcase
    end

    // Write-back data selection for Lane 0
    logic [31:0] wb_data0;
    assign wb_data0 = ex_mem_in.mem_read0 ? load_data0 : ex_mem_in.alu_result0;

    // ========================================================================
    // Lane 1 Memory Access Logic (Independent port)
    // ========================================================================

    logic [31:0] addr1;
    assign addr1 = ex_mem_in.alu_result1;

    // Byte enable generation for Lane 1
    logic [3:0] be1;
    always_comb begin
        case (ex_mem_in.mem_width1[1:0])
            `MEM_WIDTH_BYTE: be1 = 4'b0001 << addr1[1:0];
            `MEM_WIDTH_HALF: be1 = 4'b0011 << addr1[1:0];
            `MEM_WIDTH_WORD: be1 = 4'b1111;
            default:         be1 = 4'b0000;
        endcase
    end

    // Store data alignment for Lane 1
    logic [31:0] store_data1;
    always_comb begin
        case (addr1[1:0])
            2'b00: store_data1 = ex_mem_in.rs2_data1;
            2'b01: store_data1 = {ex_mem_in.rs2_data1[23:0], ex_mem_in.rs2_data1[31:24]};
            2'b10: store_data1 = {ex_mem_in.rs2_data1[15:0], ex_mem_in.rs2_data1[31:16]};
            2'b11: store_data1 = {ex_mem_in.rs2_data1[7:0],  ex_mem_in.rs2_data1[31:24]};
        endcase
    end

    // Load data for Lane 1 (uses its own dmem_rdata1 port)
    logic [31:0] load_data1;
    logic sign_ext1;
    assign sign_ext1 = ex_mem_in.mem_sign1;

    always_comb begin
        case (ex_mem_in.mem_width1[1:0])
            `MEM_WIDTH_BYTE: begin
                case (addr1[1:0])
                    2'b00: load_data1 = {{24{sign_ext1 & dmem_rdata1[7]}},  dmem_rdata1[7:0]};
                    2'b01: load_data1 = {{24{sign_ext1 & dmem_rdata1[15]}}, dmem_rdata1[15:8]};
                    2'b10: load_data1 = {{24{sign_ext1 & dmem_rdata1[23]}}, dmem_rdata1[23:16]};
                    2'b11: load_data1 = {{24{sign_ext1 & dmem_rdata1[31]}}, dmem_rdata1[31:24]};
                endcase
            end
            `MEM_WIDTH_HALF: begin
                case (addr1[1])
                    1'b0: load_data1 = {{16{sign_ext1 & dmem_rdata1[15]}}, dmem_rdata1[15:0]};
                    1'b1: load_data1 = {{16{sign_ext1 & dmem_rdata1[31]}}, dmem_rdata1[31:16]};
                endcase
            end
            `MEM_WIDTH_WORD: begin
                load_data1 = dmem_rdata1;
            end
            default: begin
                load_data1 = 32'b0;
            end
        endcase
    end

    logic [31:0] wb_data1;
    assign wb_data1 = ex_mem_in.mem_read1 ? load_data1 : ex_mem_in.alu_result1;

    // ========================================================================
    // Data Memory Port 0 Output (Lane 0 - Independent)
    // ========================================================================
    assign dmem_addr0  = (ex_mem_in.mem_read0 || ex_mem_in.mem_write0) ? addr0 : 32'b0;
    assign dmem_wdata0 = store_data0;
    assign dmem_we0    = ex_mem_in.mem_write0 & ex_mem_in.valid0;
    assign dmem_be0    = be0;

    // ========================================================================
    // Data Memory Port 1 Output (Lane 1 - Independent)
    // ========================================================================
    assign dmem_addr1  = (ex_mem_in.mem_read1 || ex_mem_in.mem_write1) ? addr1 : 32'b0;
    assign dmem_wdata1 = store_data1;
    assign dmem_we1    = ex_mem_in.mem_write1 & ex_mem_in.valid1;
    assign dmem_be1    = be1;

    // ========================================================================
    // MEM/WB Output Assembly
    // ========================================================================
    always_comb begin
        // Lane 0
        mem_wb_out.write_data0 = wb_data0;
        mem_wb_out.rd_addr0    = ex_mem_in.rd_addr0;
        mem_wb_out.reg_write0  = ex_mem_in.reg_write0 & ex_mem_in.valid0;
        mem_wb_out.valid0      = ex_mem_in.valid0;

        // Lane 1
        mem_wb_out.write_data1 = wb_data1;
        mem_wb_out.rd_addr1    = ex_mem_in.rd_addr1;
        mem_wb_out.reg_write1  = ex_mem_in.reg_write1 & ex_mem_in.valid1;
        mem_wb_out.valid1      = ex_mem_in.valid1;
    end

endmodule

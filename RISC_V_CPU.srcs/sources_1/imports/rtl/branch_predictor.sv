// ============================================================================
// Module : branch_predictor
// Project: RISC-V 2-Issue Superscalar Processor (Optimized)
// Description: Dynamic branch predictor with:
//              - BTB: 128 entries, 2-way set associative (64 sets × 2 ways)
//                Index: PC[7:2], Tag: PC[13:8]
//              - BHT: 2-bit saturating counter per BTB entry
//              - RAS: 8-entry Return Address Stack for function calls
//              - Pseudo-LRU replacement policy for BTB ways
//              - Speculative RAS update with checkpoint recovery
// ============================================================================

`include "defines.sv"

module branch_predictor (
    input  logic        clk,            // Clock
    input  logic        rst_n,          // Synchronous reset, active low

    // ----- Prediction Interface (Combinational, from Fetch Unit) -----
    input  logic [31:0] pc,             // Current fetch PC (8-byte aligned)
    output logic        bp_hit,         // Prediction is valid (BTB hit or RAS hit)
    output logic        bp_taken,       // Predict branch/jump taken
    output logic [31:0] bp_target,      // Predicted target address

    // ----- Pre-decode Info from Fetch Unit (for RAS) -----
    input  logic        pre_is_jal,     // Lane 0 inst is JAL (call)
    input  logic        pre_is_jalr,    // Lane 0 inst is JALR (potential return)
    input  logic [31:0] pre_jal_target, // JAL target address (PC + imm)

    // ----- Update Interface (from Execute Stage, synchronous) -----
    input  logic        update_valid,   // Update enable (branch/jump resolved)
    input  logic [31:0] update_pc,      // Branch/jump instruction PC
    input  logic        update_taken,   // Actual outcome (taken/not)
    input  logic [31:0] update_target,  // Actual target address
    input  logic [1:0]  update_br_type, // 00=branch, 01=JAL(call), 10=JALR(ret)

    // ----- RAS Flush (on branch mispredict) -----
    input  logic        ras_flush       // Flush speculative RAS entries
);

    // ========================================================================
    // BTB Entry Structure (optimized with branch type)
    // ========================================================================
    // br_type: 00 = conditional branch
    //          01 = JAL (unconditional call)
    //          10 = JALR (indirect jump / return)
    typedef struct packed {
        logic                         valid;      // Entry valid flag
        logic [1:0]                   br_type;    // Branch type
        logic [`BTB_TAG_BITS-1:0]     tag;        // Tag for address match
        logic [31:0]                  target;     // Stored target address
    } btb_entry_t;

    // ========================================================================
    // BTB and BHT Storage (2-way set associative)
    // ========================================================================
    btb_entry_t btb [`BTB_SETS-1:0] [`BTB_WAYS-1:0]; // BTB array
    logic [1:0] bht [`BTB_SETS-1:0] [`BTB_WAYS-1:0]; // BHT: 2-bit counters
    logic       lru [`BTB_SETS-1:0];                  // LRU: 0=way0 LRU, 1=way1 LRU

    // ========================================================================
    // RAS (Return Address Stack)
    // ========================================================================
    logic [31:0] ras [`RAS_DEPTH-1:0];  // Return address stack
    logic [2:0]  ras_ptr;               // Stack pointer (0=empty, 1-8=top index)

    // ========================================================================
    // Index and Tag Extraction
    // ========================================================================
    logic [`BTB_INDEX_BITS-1:0] pred_index;
    logic [`BTB_TAG_BITS-1:0]   pred_tag;
    logic [`BTB_INDEX_BITS-1:0] upd_index;
    logic [`BTB_TAG_BITS-1:0]   upd_tag;

    // Prediction path
    assign pred_index = pc[`BTB_INDEX_BITS+1:2];   // PC[7:2]
    assign pred_tag   = pc[`BTB_TAG_BITS+7:8];     // PC[13:8]

    // Update path
    assign upd_index = update_pc[`BTB_INDEX_BITS+1:2];
    assign upd_tag   = update_pc[`BTB_TAG_BITS+7:8];

    // ========================================================================
    // Prediction Logic (Combinational)
    // ========================================================================
    // Priority: RAS return > BTB prediction > default (sequential)
    // ========================================================================

    // BTB way comparison
    logic hit_way0, hit_way1;
    assign hit_way0 = btb[pred_index][0].valid &&
                      (btb[pred_index][0].tag == pred_tag);
    assign hit_way1 = btb[pred_index][1].valid &&
                      (btb[pred_index][1].tag == pred_tag);

    logic btb_hit;
    logic [31:0] btb_target;
    logic        btb_taken;
    assign btb_hit = hit_way0 | hit_way1;

    // Select hit way and its BHT prediction
    always_comb begin
        if (hit_way0) begin
            btb_target = btb[pred_index][0].target;
            btb_taken  = bht[pred_index][0][1];  // MSB=1 → predict taken
        end else begin
            btb_target = btb[pred_index][1].target;
            btb_taken  = bht[pred_index][1][1];
        end
    end

    // RAS return prediction: when pre_is_jalr and RAS not empty
    logic ras_return;
    assign ras_return = pre_is_jalr && (ras_ptr != 3'b0);

    // Final prediction mux
    always_comb begin
        if (ras_return) begin
            // RAS return: predict taken, target from RAS top
            bp_hit    = 1'b1;
            bp_taken  = 1'b1;
            bp_target = ras[ras_ptr - 1];
        end else if (pre_is_jal) begin
            // JAL: always predict taken, target = PC + imm (computed by fetch_unit)
            bp_hit    = 1'b1;
            bp_taken  = 1'b1;
            bp_target = pre_jal_target;
        end else if (btb_hit) begin
            // BTB hit: use BHT prediction
            bp_hit    = 1'b1;
            bp_taken  = btb_taken;
            bp_target = btb_target;
        end else begin
            // Default: sequential fetch
            bp_hit    = 1'b0;
            bp_taken  = 1'b0;
            bp_target = pc + 32'd8; // Next sequential fetch
        end
    end

    // ========================================================================
    // RAS Speculative Push/Pop (Combinational, at prediction time)
    // ========================================================================
    // On JAL: speculatively push return address (PC + 8, next aligned fetch)
    // On JALR with RAS hit: speculatively pop (the top was used for prediction)
    // ========================================================================
    logic        ras_spec_push;
    logic        ras_spec_pop;
    logic [31:0] ras_spec_push_addr;

    assign ras_spec_push = pre_is_jal;
    assign ras_spec_pop  = ras_return;
    assign ras_spec_push_addr = pc + 32'd8; // Next sequential aligned fetch

    // ========================================================================
    // RAS Pointer Management (Synchronous, posedge clk)
    // ========================================================================
    // RAS is updated speculatively at prediction time.
    // On mispredict: flush all speculative entries (reset pointer to 0).
    // This is conservative but simple and correct.
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ras_ptr <= 3'b0;
            for (int i = 0; i < `RAS_DEPTH; i++)
                ras[i] <= 32'b0;
        end else if (ras_flush) begin
            // Flush all speculative RAS entries on mispredict
            ras_ptr <= 3'b0;
        end else begin
            // Speculative push/pop at prediction time
            if (ras_spec_push && !ras_spec_pop) begin
                // Push: only push, no pop
                if (ras_ptr < `RAS_DEPTH) begin
                    ras[ras_ptr] <= ras_spec_push_addr;
                    ras_ptr <= ras_ptr + 3'd1;
                end
            end else if (!ras_spec_push && ras_spec_pop) begin
                // Pop: only pop, no push
                if (ras_ptr > 3'b0)
                    ras_ptr <= ras_ptr - 3'd1;
            end
            // If both push and pop (unlikely in same cycle), net zero change
        end
    end

    // ========================================================================
    // BTB/BHT Update and RAS Commit (Synchronous, posedge clk)
    // ========================================================================
    // On branch resolution: update BTB, BHT, and commit/deallocate RAS
    // ========================================================================
    always_ff @(posedge clk) begin
        if (update_valid) begin
            // --- Determine which way to update ---
            logic upd_way0, upd_way1;

            upd_way0 = btb[upd_index][0].valid &&
                       (btb[upd_index][0].tag == upd_tag);
            upd_way1 = btb[upd_index][1].valid &&
                       (btb[upd_index][1].tag == upd_tag);

            if (upd_way0) begin
                // Hit in way 0: update way 0
                btb[upd_index][0].target  <= update_target;
                btb[upd_index][0].br_type <= update_br_type;
                // Update LRU: way 0 accessed, way 1 is LRU
                lru[upd_index] <= 1'b1;
                // Update BHT counter for way 0
                if (update_taken) begin
                    if (bht[upd_index][0] < 2'b11)
                        bht[upd_index][0] <= bht[upd_index][0] + 2'b01;
                end else begin
                    if (bht[upd_index][0] > 2'b00)
                        bht[upd_index][0] <= bht[upd_index][0] - 2'b01;
                end

            end else if (upd_way1) begin
                // Hit in way 1: update way 1
                btb[upd_index][1].target  <= update_target;
                btb[upd_index][1].br_type <= update_br_type;
                // Update LRU: way 1 accessed, way 0 is LRU
                lru[upd_index] <= 1'b0;
                // Update BHT counter for way 1
                if (update_taken) begin
                    if (bht[upd_index][1] < 2'b11)
                        bht[upd_index][1] <= bht[upd_index][1] + 2'b01;
                end else begin
                    if (bht[upd_index][1] > 2'b00)
                        bht[upd_index][1] <= bht[upd_index][1] - 2'b01;
                end

            end else begin
                // Miss: allocate in LRU way
                if (lru[upd_index] == 1'b0) begin
                    // Way 0 is LRU: allocate in way 0
                    btb[upd_index][0].valid   <= 1'b1;
                    btb[upd_index][0].tag     <= upd_tag;
                    btb[upd_index][0].target  <= update_target;
                    btb[upd_index][0].br_type <= update_br_type;
                    lru[upd_index] <= 1'b1; // Way 0 just used, way 1 is now LRU
                    // Initialize BHT
                    bht[upd_index][0] <= update_taken ? 2'b10 : 2'b01;
                end else begin
                    // Way 1 is LRU: allocate in way 1
                    btb[upd_index][1].valid   <= 1'b1;
                    btb[upd_index][1].tag     <= upd_tag;
                    btb[upd_index][1].target  <= update_target;
                    btb[upd_index][1].br_type <= update_br_type;
                    lru[upd_index] <= 1'b0; // Way 1 just used, way 0 is now LRU
                    // Initialize BHT
                    bht[upd_index][1] <= update_taken ? 2'b10 : 2'b01;
                end
            end

            // RAS is updated speculatively at prediction time (push/pop).
            // On mispredict, ras_flush resets the RAS pointer.
            // No additional commit logic needed here.
        end

        if (!rst_n) begin
            for (int i = 0; i < `BTB_SETS; i++) begin
                btb[i][0].valid <= 1'b0;
                btb[i][1].valid <= 1'b0;
                btb[i][0].tag   <= '0;
                btb[i][1].tag   <= '0;
                btb[i][0].target <= 32'b0;
                btb[i][1].target <= 32'b0;
                bht[i][0] <= 2'b00;
                bht[i][1] <= 2'b00;
                lru[i]    <= 1'b0;
            end
        end
    end

endmodule

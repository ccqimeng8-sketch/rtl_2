// ============================================================================
// 模块 : branch_predictor
// 项目 : RISC-V 双发射超标量处理器（优化版）
// 说明 : 动态分支预测器，包含：
//        - BTB：128条目，2路组相连（64组 × 2路）
//          索引：PC[7:2]，标签：PC[13:8]
//        - BHT：每个BTB条目对应一个2位饱和计数器
//        - RAS：8条目返回地址栈，用于函数调用
//        - 伪LRU替换策略，用于BTB多路选择
//        - 带检查点恢复的推测性RAS更新
// ============================================================================

`include "defines.sv"

module branch_predictor (
    input  logic        clk,            // 时钟
    input  logic        rst_n,          // 同步复位，低有效

    // ----- 预测接口（组合逻辑，来自取指单元）-----
    input  logic [31:0] pc,             // 当前取指PC（8字节对齐）
    output logic        bp_hit,         // 预测有效（BTB命中或RAS命中）
    output logic        bp_taken,       // 预测分支/跳转为跳转
    output logic [31:0] bp_target,      // 预测目标地址

    // ----- 来自取指单元的预解码信息（用于RAS）-----
    input  logic        pre_is_jal,     // Lane 0指令为JAL（调用）
    input  logic        pre_is_jalr,    // Lane 0指令为JALR（可能的返回）
    input  logic [31:0] pre_jal_target, // JAL目标地址（PC + 立即数）

    // ----- 更新接口（来自执行阶段，同步）-----
    input  logic        update_valid,   // 更新使能（分支/跳转已解析）
    input  logic [31:0] update_pc,      // 分支/跳转指令PC
    input  logic        update_taken,   // 实际结果（跳转/不跳转）
    input  logic [31:0] update_target,  // 实际目标地址
    input  logic [1:0]  update_br_type, // 00=分支, 01=JAL(调用), 10=JALR(返回)

    // ----- RAS刷新（分支预测错误时）-----
    input  logic        ras_flush       // 刷新推测性RAS条目
);

    // ========================================================================
    // BTB条目结构（优化后，包含分支类型）
    // ========================================================================
    // br_type: 00 = 条件分支
    //          01 = JAL（无条件调用）
    //          10 = JALR（间接跳转 / 返回）
    typedef struct packed {
        logic                         valid;      // 条目有效标志
        logic [1:0]                   br_type;    // 分支类型
        logic [`BTB_TAG_BITS-1:0]     tag;        // 地址匹配标签
        logic [31:0]                  target;     // 存储的目标地址
    } btb_entry_t;

    // ========================================================================
    // BTB与BHT存储（2路组相连）
    // ========================================================================
    btb_entry_t btb [`BTB_SETS-1:0] [`BTB_WAYS-1:0]; // BTB数组
    logic [1:0] bht [`BTB_SETS-1:0] [`BTB_WAYS-1:0]; // BHT：2位计数器
    logic       lru [`BTB_SETS-1:0];                  // LRU：0=way0为LRU, 1=way1为LRU

    // ========================================================================
    // RAS（返回地址栈）
    // ========================================================================
    logic [31:0] ras [`RAS_DEPTH-1:0];  // 返回地址栈
    logic [2:0]  ras_ptr;               // 栈指针（0=空, 1-8=栈顶索引）

    // ========================================================================
    // 索引与标签提取
    // ========================================================================
    logic [`BTB_INDEX_BITS-1:0] pred_index;
    logic [`BTB_TAG_BITS-1:0]   pred_tag;
    logic [`BTB_INDEX_BITS-1:0] upd_index;
    logic [`BTB_TAG_BITS-1:0]   upd_tag;

    // 预测路径
    assign pred_index = pc[`BTB_INDEX_BITS+1:2];   // PC[7:2]
    assign pred_tag   = pc[`BTB_TAG_BITS+7:8];     // PC[13:8]

    // 更新路径
    assign upd_index = update_pc[`BTB_INDEX_BITS+1:2];
    assign upd_tag   = update_pc[`BTB_TAG_BITS+7:8];

    // ========================================================================
    // 预测逻辑（组合逻辑）
    // ========================================================================
    // 优先级：RAS返回 > BTB预测 > 默认（顺序执行）
    // ========================================================================

    // BTB路比较
    logic hit_way0, hit_way1;
    assign hit_way0 = btb[pred_index][0].valid &&
                      (btb[pred_index][0].tag == pred_tag);
    assign hit_way1 = btb[pred_index][1].valid &&
                      (btb[pred_index][1].tag == pred_tag);

    logic btb_hit;
    logic [31:0] btb_target;
    logic        btb_taken;
    assign btb_hit = hit_way0 | hit_way1;

    // 选择命中路及其BHT预测
    always_comb begin
        if (hit_way0) begin
            btb_target = btb[pred_index][0].target;
            btb_taken  = bht[pred_index][0][1];  // MSB=1 → 预测跳转
        end else begin
            btb_target = btb[pred_index][1].target;
            btb_taken  = bht[pred_index][1][1];
        end
    end

    // RAS返回预测：当pre_is_jalr且RAS非空时
    logic ras_return;
    assign ras_return = pre_is_jalr && (ras_ptr != 3'b0);

    // 最终预测多路选择
    always_comb begin
        if (ras_return) begin
            // RAS返回：预测跳转，目标来自RAS栈顶
            bp_hit    = 1'b1;
            bp_taken  = 1'b1;
            bp_target = ras[ras_ptr - 1];
        end else if (pre_is_jal) begin
            // JAL：始终预测跳转，目标 = PC + 立即数（由取指单元计算）
            bp_hit    = 1'b1;
            bp_taken  = 1'b1;
            bp_target = pre_jal_target;
        end else if (btb_hit) begin
            // BTB命中：使用BHT预测
            bp_hit    = 1'b1;
            bp_taken  = btb_taken;
            bp_target = btb_target;
        end else begin
            // 默认：顺序取指
            bp_hit    = 1'b0;
            bp_taken  = 1'b0;
            bp_target = pc + 32'd8; // 下一个顺序取指
        end
    end

    // ========================================================================
    // RAS推测性压栈/弹栈（组合逻辑，预测时使用）
    // ========================================================================
    // JAL时：推测性压入返回地址（PC + 8，下一个对齐取指）
    // JALR且RAS命中时：推测性弹栈（栈顶已用于预测）
    // ========================================================================
    logic        ras_spec_push;
    logic        ras_spec_pop;
    logic [31:0] ras_spec_push_addr;

    assign ras_spec_push = pre_is_jal;
    assign ras_spec_pop  = ras_return;
    assign ras_spec_push_addr = pc + 32'd8; // 下一个顺序对齐取指

    // ========================================================================
    // RAS指针管理（同步，posedge clk）
    // ========================================================================
    // RAS在预测时进行推测性更新。
    // 预测错误时：刷新所有推测性条目（重置指针为0）。
    // 此方法较为保守，但简单且正确。
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ras_ptr <= 3'b0;
            for (int i = 0; i < `RAS_DEPTH; i++)
                ras[i] <= 32'b0;
        end else if (ras_flush) begin
            // 分支预测错误时刷新所有推测性RAS条目
            ras_ptr <= 3'b0;
        end else begin
            // 预测时刻的推测性压栈/弹栈
            if (ras_spec_push && !ras_spec_pop) begin
                // 压栈：仅压栈，不弹栈
                if (ras_ptr < `RAS_DEPTH) begin
                    ras[ras_ptr] <= ras_spec_push_addr;
                    ras_ptr <= ras_ptr + 3'd1;
                end
            end else if (!ras_spec_push && ras_spec_pop) begin
                // 弹栈：仅弹栈，不压栈
                if (ras_ptr > 3'b0)
                    ras_ptr <= ras_ptr - 3'd1;
            end
            // 若同一周期同时压栈和弹栈（不太可能），净变化为零
        end
    end

    // ========================================================================
    // BTB/BHT更新与RAS提交（同步，posedge clk）
    // ========================================================================
    // 分支解析时：更新BTB、BHT，并提交/释放RAS
    // ========================================================================
    always_ff @(posedge clk) begin
        if (update_valid) begin
            // --- 确定要更新哪一路 ---
            logic upd_way0, upd_way1;

            upd_way0 = btb[upd_index][0].valid &&
                       (btb[upd_index][0].tag == upd_tag);
            upd_way1 = btb[upd_index][1].valid &&
                       (btb[upd_index][1].tag == upd_tag);

            if (upd_way0) begin
                // 命中 way 0：更新 way 0
                btb[upd_index][0].target  <= update_target;
                btb[upd_index][0].br_type <= update_br_type;
                // 更新LRU：way 0被访问，way 1为LRU
                lru[upd_index] <= 1'b1;
                // 更新 way 0 的BHT计数器
                if (update_taken) begin
                    if (bht[upd_index][0] < 2'b11)
                        bht[upd_index][0] <= bht[upd_index][0] + 2'b01;
                end else begin
                    if (bht[upd_index][0] > 2'b00)
                        bht[upd_index][0] <= bht[upd_index][0] - 2'b01;
                end

            end else if (upd_way1) begin
                // 命中 way 1：更新 way 1
                btb[upd_index][1].target  <= update_target;
                btb[upd_index][1].br_type <= update_br_type;
                // 更新LRU：way 1被访问，way 0为LRU
                lru[upd_index] <= 1'b0;
                // 更新 way 1 的BHT计数器
                if (update_taken) begin
                    if (bht[upd_index][1] < 2'b11)
                        bht[upd_index][1] <= bht[upd_index][1] + 2'b01;
                end else begin
                    if (bht[upd_index][1] > 2'b00)
                        bht[upd_index][1] <= bht[upd_index][1] - 2'b01;
                end

            end else begin
                // 未命中：在LRU路中分配
                if (lru[upd_index] == 1'b0) begin
                    // Way 0为LRU：在way 0中分配
                    btb[upd_index][0].valid   <= 1'b1;
                    btb[upd_index][0].tag     <= upd_tag;
                    btb[upd_index][0].target  <= update_target;
                    btb[upd_index][0].br_type <= update_br_type;
                    lru[upd_index] <= 1'b1; // Way 0刚被使用，way 1现在是LRU
                    // 初始化BHT
                    bht[upd_index][0] <= update_taken ? 2'b10 : 2'b01;
                end else begin
                    // Way 1为LRU：在way 1中分配
                    btb[upd_index][1].valid   <= 1'b1;
                    btb[upd_index][1].tag     <= upd_tag;
                    btb[upd_index][1].target  <= update_target;
                    btb[upd_index][1].br_type <= update_br_type;
                    lru[upd_index] <= 1'b0; // Way 1刚被使用，way 0现在是LRU
                    // 初始化BHT
                    bht[upd_index][1] <= update_taken ? 2'b10 : 2'b01;
                end
            end

            // RAS在预测时进行推测性更新（压栈/弹栈）。
            // 预测错误时，ras_flush会重置RAS指针。
            // 此处不需要额外的提交逻辑。
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

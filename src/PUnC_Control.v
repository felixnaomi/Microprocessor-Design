//==============================================================================
// Control Unit for PUnC LC3 Processor
//==============================================================================

`include "Defines.v"

module PUnCControl(
    // External Inputs
    input  wire        clk,
    input  wire        rst,
    
    // Inputs from Datapath
    input  wire [15:0] ir_out,  // To read Opcode and Mode bits
    input  wire        n, z, p, // Condition codes for Branch logic

    // Datapath Control Outputs
    output reg  [1:0]  pc_mux_sel,
    output reg  [1:0]  alu_src_a_sel,
    output reg  [2:0]  alu_src_b_sel,
    output reg  [1:0]  alu_op,
    output reg  [1:0]  rf_w_data_sel,
    output reg         rf_w_addr_sel,
    output reg         rf_r_addr_1_sel,
    output reg         rf_we,
    output reg         mem_we,
    output reg         ir_load,
    output reg         nzp_we,
    output reg         temp_load,
    output reg         pc_we
);

    //==========================================================================
    // FSM States
    //==========================================================================
    localparam STATE_FETCH   = 5'd0;
    localparam STATE_DECODE  = 5'd1;
    localparam STATE_ADD     = 5'd2;
    localparam STATE_AND     = 5'd3;
    localparam STATE_NOT     = 5'd4;
    localparam STATE_LD      = 5'd5;
    localparam STATE_LDR     = 5'd6;
    localparam STATE_LDI_1   = 5'd7;
    localparam STATE_LDI_2   = 5'd8;
    localparam STATE_LEA     = 5'd9;
    localparam STATE_ST      = 5'd10;
    localparam STATE_STR     = 5'd11;
    localparam STATE_STI_1   = 5'd12;
    localparam STATE_STI_2   = 5'd13;
    localparam STATE_BR      = 5'd14;
    localparam STATE_JMP     = 5'd15; // Covers JMP and RET
    localparam STATE_JSR     = 5'd16; // Covers JSR and JSRR
    localparam STATE_HALT    = 5'd31;

    reg [4:0] state, next_state;

    // Helper wires for decoding
    wire [3:0] opcode = ir_out[15:12];
    wire       imm_mode = ir_out[5]; // For ADD/AND
    wire       jsr_mode = ir_out[11]; // 1=JSR, 0=JSRR

    //==========================================================================
    // 1. State Update Sequential Logic
    //==========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_FETCH;
        end
        else begin
            state <= next_state;
        end
    end

    //==========================================================================
    // 2. Next State Logic (The Decoder)
    //==========================================================================
    always @( * ) begin
        // Default: Stay in current state (prevents latches)
        next_state = state;

        case (state)
            STATE_FETCH:   next_state = STATE_DECODE;
            
            STATE_DECODE: begin
                // Decode Opcode to decide Execution State
                case (opcode)
                    `OC_ADD: next_state = STATE_ADD;
                    `OC_AND: next_state = STATE_AND;
                    `OC_NOT: next_state = STATE_NOT;
                    `OC_LD:  next_state = STATE_LD;
                    `OC_LDR: next_state = STATE_LDR;
                    `OC_LDI: next_state = STATE_LDI_1;
                    `OC_LEA: next_state = STATE_LEA;
                    `OC_ST:  next_state = STATE_ST;
                    `OC_STR: next_state = STATE_STR;
                    `OC_STI: next_state = STATE_STI_1;
                    `OC_BR:  next_state = STATE_BR;
                    `OC_JMP: next_state = STATE_JMP; // RET is same opcode
                    `OC_JSR: next_state = STATE_JSR;
                    `OC_HLT: next_state = STATE_HALT;
                    default: next_state = STATE_FETCH; // Error recovery
                endcase
            end

            // Single Cycle Execution -> Go back to Fetch
            STATE_ADD, STATE_AND, STATE_NOT, 
            STATE_LD, STATE_LDR, STATE_LEA, 
            STATE_ST, STATE_STR, 
            STATE_BR, STATE_JMP, STATE_JSR: begin
                next_state = STATE_FETCH;
            end

            // Multi-Cycle Execution
            STATE_LDI_1: next_state = STATE_LDI_2;
            STATE_LDI_2: next_state = STATE_FETCH;
            
            STATE_STI_1: next_state = STATE_STI_2;
            STATE_STI_2: next_state = STATE_FETCH;

            // HALT traps here forever
            STATE_HALT: next_state = STATE_HALT;

        endcase
    end

    //==========================================================================
    // 3. Output Combinational Logic (The Control Signal Table)
    //==========================================================================
    always @( * ) begin
        // ---------------------------------------------------------------------
        // Defaults (Set everything to 0/Safe to prevent implicit latches)
        // ---------------------------------------------------------------------
        pc_mux_sel      = 2'b00; // Inc
        alu_src_a_sel   = 2'b00; // RF
        alu_src_b_sel   = 3'b000;
        alu_op          = 2'b00; // Add
        rf_w_data_sel   = 2'b00; // ALU
        rf_w_addr_sel   = 1'b0;  // DR
        rf_r_addr_1_sel = 1'b0;  // SR2
        rf_we           = 1'b0;
        mem_we          = 1'b0;
        ir_load         = 1'b0;
        nzp_we          = 1'b0;
        temp_load       = 1'b0;
        pc_we           = 1'b0;  // Default PC frozen, except listed below

        case (state)
            
            // -----------------------------------------------------------------
            // FETCH: IR <= Mem[PC]
            // -----------------------------------------------------------------
            STATE_FETCH: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                // ALU pass A (Add + 0)
                alu_src_b_sel = `ALU_SRC_B_SEL_ZERO; 
                alu_op        = `ALU_OP_ADD;
                
                mem_we        = 1'b0; // Read
                ir_load       = 1'b1; // Load IR
                pc_we         = 1'b0; // Freeze PC
            end

            // -----------------------------------------------------------------
            // DECODE: PC <= PC + 1
            // -----------------------------------------------------------------
            STATE_DECODE: begin
                pc_mux_sel    = `PC_MUX_SEL_INC;
                pc_we         = 1'b1; // Update PC
            end

            // -----------------------------------------------------------------
            // ARITHMETIC: ADD, AND, NOT
            // -----------------------------------------------------------------
            STATE_ADD: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_RF;
                // Check Bit 5 for Immediate Mode
                alu_src_b_sel = (imm_mode) ? `ALU_SRC_B_SEL_IMM5 : `ALU_SRC_B_SEL_RF;
                alu_op        = `ALU_OP_ADD;
                
                rf_w_data_sel = `RF_W_DATA_SEL_ALU;
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end

            STATE_AND: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_RF;
                alu_src_b_sel = (imm_mode) ? `ALU_SRC_B_SEL_IMM5 : `ALU_SRC_B_SEL_RF;
                alu_op        = `ALU_OP_AND;
                
                rf_w_data_sel = `RF_W_DATA_SEL_ALU;
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end

            STATE_NOT: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_RF;
                alu_op        = `ALU_OP_NOT;
                
                rf_w_data_sel = `RF_W_DATA_SEL_ALU;
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end

            // -----------------------------------------------------------------
            // MEMORY: LD, LDR, LEA (Loads)
            // -----------------------------------------------------------------
            STATE_LD: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                alu_src_b_sel = `ALU_SRC_B_SEL_PC9;
                alu_op        = `ALU_OP_ADD;
                
                rf_w_data_sel = `RF_W_DATA_SEL_MEM;
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end

            STATE_LDR: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_RF;
                alu_src_b_sel = `ALU_SRC_B_SEL_OFF6;
                alu_op        = `ALU_OP_ADD;
                
                rf_w_data_sel = `RF_W_DATA_SEL_MEM;
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end
            
            STATE_LEA: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                alu_src_b_sel = `ALU_SRC_B_SEL_PC9;
                alu_op        = `ALU_OP_ADD;
                
                rf_w_data_sel = `RF_W_DATA_SEL_ALU; // Save Address, not Mem
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end

            // -----------------------------------------------------------------
            // MEMORY: ST, STR (Stores)
            // -----------------------------------------------------------------
            STATE_ST: begin
                alu_src_a_sel   = `ALU_SRC_A_SEL_PC;
                alu_src_b_sel   = `ALU_SRC_B_SEL_PC9;
                alu_op          = `ALU_OP_ADD;
                
                rf_r_addr_1_sel = `RF_R_ADDR_1_SEL_SR; // Data from SR
                mem_we          = 1'b1;
            end

            STATE_STR: begin
                alu_src_a_sel   = `ALU_SRC_A_SEL_RF;
                alu_src_b_sel   = `ALU_SRC_B_SEL_OFF6;
                alu_op          = `ALU_OP_ADD;
                
                rf_r_addr_1_sel = `RF_R_ADDR_1_SEL_SR; // Data from SR
                mem_we          = 1'b1;
            end

            // -----------------------------------------------------------------
            // INDIRECT: LDI (2 Cycles)
            // -----------------------------------------------------------------
            STATE_LDI_1: begin
                // Calc Pointer Address, Load to Temp
                alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                alu_src_b_sel = `ALU_SRC_B_SEL_PC9;
                alu_op        = `ALU_OP_ADD;
                temp_load     = 1'b1;
            end

            STATE_LDI_2: begin
                // Read from Temp Address, Load to RF
                alu_src_a_sel = `ALU_SRC_A_SEL_TEMP;
                alu_src_b_sel = `ALU_SRC_B_SEL_ZERO; // Pass through
                alu_op        = `ALU_OP_ADD;
                
                rf_w_data_sel = `RF_W_DATA_SEL_MEM;
                rf_w_addr_sel = `RF_W_ADDR_SEL_DR;
                rf_we         = 1'b1;
                nzp_we        = 1'b1;
            end

            // -----------------------------------------------------------------
            // INDIRECT: STI (2 Cycles)
            // -----------------------------------------------------------------
            STATE_STI_1: begin
                // Calc Pointer Address, Load to Temp
                alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                alu_src_b_sel = `ALU_SRC_B_SEL_PC9;
                alu_op        = `ALU_OP_ADD;
                temp_load     = 1'b1;
            end
            
            STATE_STI_2: begin
                // Write SR to address in Temp
                alu_src_a_sel   = `ALU_SRC_A_SEL_TEMP;
                alu_src_b_sel   = `ALU_SRC_B_SEL_ZERO;
                alu_op          = `ALU_OP_ADD;
                
                rf_r_addr_1_sel = `RF_R_ADDR_1_SEL_SR; // Data from SR
                mem_we          = 1'b1;
            end

            // -----------------------------------------------------------------
            // BRANCH: BR
            // -----------------------------------------------------------------
            STATE_BR: begin
                alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                alu_src_b_sel = `ALU_SRC_B_SEL_PC9;
                alu_op        = `ALU_OP_ADD;
                
                // Check Logic: if ( (n&N) | (z&Z) | (p&P) )
                if ((ir_out[11] & n) | (ir_out[10] & z) | (ir_out[9] & p)) begin
                    pc_mux_sel = `PC_MUX_SEL_ALU;
                    pc_we      = 1'b1;
                end else begin
                    pc_we      = 1'b0; // Don't take branch
                end
            end

            // -----------------------------------------------------------------
            // JUMP: JMP, RET
            // -----------------------------------------------------------------
            STATE_JMP: begin
                // BaseR is in SR1 bits (8:6), which is default Read Port 0
                pc_mux_sel = `PC_MUX_SEL_RF;
                pc_we      = 1'b1;
            end

            // -----------------------------------------------------------------
            // SUBROUTINE: JSR, JSRR
            // -----------------------------------------------------------------
            STATE_JSR: begin
                // 1. Save Return Address (PC) to R7
                rf_w_data_sel = `RF_W_DATA_SEL_PC;
                rf_w_addr_sel = `RF_W_ADDR_SEL_R7; // Force R7
                rf_we         = 1'b1;
                
                // 2. Update PC
                pc_we = 1'b1;
                if (jsr_mode) begin
                    // JSR: PC + Offset11
                    alu_src_a_sel = `ALU_SRC_A_SEL_PC;
                    alu_src_b_sel = `ALU_SRC_B_SEL_PC11;
                    alu_op        = `ALU_OP_ADD;
                    pc_mux_sel    = `PC_MUX_SEL_ALU;
                end else begin
                    // JSRR: BaseR
                    pc_mux_sel    = `PC_MUX_SEL_RF;
                end
            end

            // -----------------------------------------------------------------
            // HALT
            // -----------------------------------------------------------------
            STATE_HALT: begin
                // Do nothing. PC is frozen (pc_we default is 0).
                // State stays in HALT.
            end

        endcase
    end

endmodule


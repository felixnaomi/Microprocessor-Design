`include "Defines.v"

module PUnCDatapath(
    input  wire        clk,
    input  wire        rst,

    // Control Signals (From Controller)
    input  wire [1:0]  pc_mux_sel,
    input  wire [1:0]  alu_src_a_sel,
    input  wire [2:0]  alu_src_b_sel,
    input  wire [1:0]  alu_op,
    input  wire [1:0]  rf_w_data_sel,
    input  wire        rf_w_addr_sel,
    input  wire        rf_r_addr_1_sel,
    input  wire        rf_we,
    input  wire        mem_we,
    input  wire        ir_load,
    input  wire        nzp_we,
    input  wire        temp_load, // New signal for Temp Reg
    input  wire        pc_we,     // New signal for HALT freeze

    // Output Signals (To Controller)
    output wire [15:0] ir_out,    // Controller needs Opcode
    output wire        n, z, p,   // Controller needs Flags for BR

    // Debug Signals (Do not touch these)
    input  wire [15:0] mem_debug_addr,
    input  wire [2:0]  rf_debug_addr,
    output wire [15:0] mem_debug_data,
    output wire [15:0] rf_debug_data,
    output wire [15:0] pc_debug_data
);

    //==========================================================================
    // Internal Signals (Wires & Regs)
    //==========================================================================
    reg  [15:0] pc;
    reg  [15:0] ir;
    reg  [15:0] temp_reg;      // The "Temp" register for LDI/STI
    reg         n_reg, z_reg, p_reg;

    wire [15:0] pc_next;
    wire [15:0] pc_plus_one;
    
    // Memory Connections
    wire [15:0] mem_r_data;
    
    // Register File Connections
    wire [2:0]  rf_r_addr_1;
    wire [2:0]  rf_w_addr;
    wire [15:0] rf_w_data;
    wire [15:0] rf_r_data_0;
    wire [15:0] rf_r_data_1;

    // ALU Connections
    reg  [15:0] alu_out;       // Output of ALU Logic
    reg  [15:0] alu_in_a;      // Output of Mux A
    reg  [15:0] alu_in_b;      // Output of Mux B

    // Sign Extended Values (Helper wires)
    wire [15:0] sext_imm5   = {{11{ir[4]}}, ir[4:0]};
    wire [15:0] sext_off6   = {{10{ir[5]}}, ir[5:0]};
    wire [15:0] sext_pc9    = {{7{ir[8]}},  ir[8:0]};
    wire [15:0] sext_pc11   = {{5{ir[10]}}, ir[10:0]};


    //==========================================================================
    // 1. Program Counter (PC) Logic
    //==========================================================================
    assign pc_plus_one = pc + 16'd1;
    assign pc_debug_data = pc; // Required for debug

    // The PC MUX
    assign pc_next = (pc_mux_sel == `PC_MUX_SEL_ALU) ? alu_out :
                     (pc_mux_sel == `PC_MUX_SEL_RF)  ? rf_r_data_0 :
                     pc_plus_one; // Default `PC_MUX_SEL_INC

    // The PC Register
    always @(posedge clk) begin
        if (rst) 
            pc <= 16'd0;
        else if (pc_we)  // We added this Enable for HALT!
            pc <= pc_next;
    end

    //==========================================================================
    // 2. Instruction Register (IR)
    //==========================================================================
    always @(posedge clk) begin
        if (rst)
            ir <= 16'd0;
        else if (ir_load)
            ir <= mem_r_data;
    end
    
    assign ir_out = ir; // Send IR to controller

    //==========================================================================
    // 3. Temp Register (For LDI/STI)
    //==========================================================================
    always @(posedge clk) begin
        if (rst)
            temp_reg <= 16'd0;
        else if (temp_load)
            temp_reg <= mem_r_data;
    end

    //==========================================================================
    // 4. Multiplexers (The Routing Logic)
    //==========================================================================
    
    // ALU Input A Mux
    always @(*) begin
        case (alu_src_a_sel)
            `ALU_SRC_A_SEL_RF:       alu_in_a = rf_r_data_0;
            `ALU_SRC_A_SEL_PC:   alu_in_a = pc;
            `ALU_SRC_A_SEL_TEMP:     alu_in_a = temp_reg;
            default:                 alu_in_a = 16'd0;
        endcase
    end

    // ALU Input B Mux
    always @(*) begin
        case (alu_src_b_sel)
            `ALU_SRC_B_SEL_RF:   alu_in_b = rf_r_data_1;
            `ALU_SRC_B_SEL_IMM5: alu_in_b = sext_imm5;
            `ALU_SRC_B_SEL_OFF6: alu_in_b = sext_off6;
            `ALU_SRC_B_SEL_PC9:  alu_in_b = sext_pc9;
            `ALU_SRC_B_SEL_PC11: alu_in_b = sext_pc11;
            `ALU_SRC_B_SEL_ZERO: alu_in_b = 16'd0;
            default:             alu_in_b = 16'd0;
        endcase
    end

    // Register File MUXes
    // Select between SR2 (bits 2:0) or SR (bits 11:9) for Read Port 1
    assign rf_r_addr_1 = (rf_r_addr_1_sel == `RF_R_ADDR_1_SEL_SR) ? ir[11:9] : ir[2:0];

    // Select between DR (bits 11:9) or R7 (hardcoded) for Write Address
    assign rf_w_addr   = (rf_w_addr_sel == `RF_W_ADDR_SEL_R7) ? 3'b111 : ir[11:9];

    // Select Data source for RF Write
    assign rf_w_data   = (rf_w_data_sel == `RF_W_DATA_SEL_MEM) ? mem_r_data :
                         (rf_w_data_sel == `RF_W_DATA_SEL_PC)  ? pc:
                         alu_out; // Default ALU

    //==========================================================================
    // 5. The ALU (Arithmetic Logic Unit)
    //==========================================================================
    always @(*) begin
        case (alu_op)
            `ALU_OP_ADD: alu_out = alu_in_a + alu_in_b;
            `ALU_OP_AND: alu_out = alu_in_a & alu_in_b;
            `ALU_OP_NOT: alu_out = ~alu_in_a;
            default:     alu_out = 16'd0;
        endcase
    end

    //==========================================================================
    // 6. Condition Codes (N, Z, P)
    //==========================================================================
    
    // Output these to the controller
    assign n = n_reg;
    assign z = z_reg;
    assign p = p_reg;

    always @(posedge clk) begin
        if (rst) begin
            n_reg <= 0;
            z_reg <= 0;
            p_reg <= 0;
        end else if (nzp_we) begin
            // Check the logic on the WRITE DATA wire (before it hits the register)
            n_reg <= rf_w_data[15];          // MSB is 1
            z_reg <= (rf_w_data == 16'd0);   // All zeros
            p_reg <= (!rf_w_data[15] && (rf_w_data != 0));
        end
    end

    //==========================================================================
    // 7. Core Module Instantiations
    //==========================================================================

    Memory mem(
        .clk      (clk),
        .rst      (rst),
        .r_addr_0 (alu_out),      // Address always comes from ALU
        .r_addr_1 (mem_debug_addr),
        .w_addr   (alu_out),
        .w_data   (rf_r_data_1),  // Data always comes from RF Port 1
        .w_en     (mem_we),
        .r_data_0 (mem_r_data),
        .r_data_1 (mem_debug_data)
    );

    RegisterFile rfile(
        .clk      (clk),
        .rst      (rst),
        .r_addr_0 (ir[8:6]),       // Always BaseR / SR1
        .r_addr_1 (rf_r_addr_1),   // Muxed SR2 / SR
        .r_addr_2 (rf_debug_addr),
        .w_addr   (rf_w_addr),     // Muxed DR / R7
        .w_data   (rf_w_data),     // Muxed ALU / Mem / PC
        .w_en     (rf_we),
        .r_data_0 (rf_r_data_0),
        .r_data_1 (rf_r_data_1),
        .r_data_2 (rf_debug_data)
    );

endmodule

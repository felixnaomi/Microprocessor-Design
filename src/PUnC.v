`include "Defines.v"

module PUnC(
    input  wire        clk,
    input  wire        rst,
    
    // Debug Ports
    input  wire [15:0] mem_debug_addr,
    input  wire [2:0]  rf_debug_addr,
    output wire [15:0] mem_debug_data,
    output wire [15:0] rf_debug_data,
    output wire [15:0] pc_debug_data
);

    //==========================================================================
    // Interconnect Wires (Connecting Control to Datapath)
    //==========================================================================
    
    // From Datapath to Control
    wire [15:0] ir_out;
    wire        n, z, p;
    
    // From Control to Datapath
    wire [1:0]  pc_mux_sel;
    wire [1:0]  alu_src_a_sel;
    wire [2:0]  alu_src_b_sel;
    wire [1:0]  alu_op;
    wire [1:0]  rf_w_data_sel;
    wire        rf_w_addr_sel;
    wire        rf_r_addr_1_sel;
    wire        rf_we;
    wire        mem_we;
    wire        ir_load;
    wire        nzp_we;
    wire        temp_load;
    wire        pc_we;

    //==========================================================================
    // Module Instantiations
    //==========================================================================

    PUnCDatapath dpath(
        .clk              (clk),
        .rst              (rst),
        
        // Control Inputs
        .pc_mux_sel       (pc_mux_sel),
        .alu_src_a_sel    (alu_src_a_sel),
        .alu_src_b_sel    (alu_src_b_sel),
        .alu_op           (alu_op),
        .rf_w_data_sel    (rf_w_data_sel),
        .rf_w_addr_sel    (rf_w_addr_sel),
        .rf_r_addr_1_sel  (rf_r_addr_1_sel),
        .rf_we            (rf_we),
        .mem_we           (mem_we),
        .ir_load          (ir_load),
        .nzp_we           (nzp_we),
        .temp_load        (temp_load),
        .pc_we            (pc_we),
        
        // Outputs to Control
        .ir_out           (ir_out),
        .n(n), .z(z), .p(p),
        
        // Debug Connections
        .mem_debug_addr   (mem_debug_addr),
        .rf_debug_addr    (rf_debug_addr),
        .mem_debug_data   (mem_debug_data),
        .rf_debug_data    (rf_debug_data),
        .pc_debug_data    (pc_debug_data)
    );

    PUnCControl ctrl(
        .clk              (clk),
        .rst              (rst),
        
        // Inputs from Datapath
        .ir_out           (ir_out),
        .n(n), .z(z), .p(p),
        
        // Control Outputs
        .pc_mux_sel       (pc_mux_sel),
        .alu_src_a_sel    (alu_src_a_sel),
        .alu_src_b_sel    (alu_src_b_sel),
        .alu_op           (alu_op),
        .rf_w_data_sel    (rf_w_data_sel),
        .rf_w_addr_sel    (rf_w_addr_sel),
        .rf_r_addr_1_sel  (rf_r_addr_1_sel),
        .rf_we            (rf_we),
        .mem_we           (mem_we),
        .ir_load          (ir_load),
        .nzp_we           (nzp_we),
        .temp_load        (temp_load),
        .pc_we            (pc_we)
    );

endmodule

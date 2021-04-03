/*
 * @Name         : cardinal_cpu
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-25 11:17:56
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-04-02 17:46:56
 * @Description  : 
                A variable-width 4-stage pipelined processor that executes all the 
                instructions in the Cardinal Processor Instruction Set Manual. (Since Load/Store instructions 
                use only immediate address specifiers, memory operations can be performed in the same stage 
                as ALU functions; therefore, a 4-stage pipeline results). 
                The pipeline stages are then:
                    a. Instruction Fetch (IF)
                    b. Instruction Decode and Register Fetch (ID) 
                    c. Execution or Memory Access (EX/MEM) 
                    d. Write Back (WB)
 */

module cardinal_cpu (
//--------------------------------------PORTS-------------------------------------------------
    // control
    input clk, // clock signal
    input reset, // synchronous active high reset

    // asynchronous read instruction memory                         (imem           )
    output  [0:31]  pc_out, // pc out for fetching instructions     (.memAddr       )
    input   [0:31]  inst_in, // instructions input from imem        (.dataOut       )
    
    // asynchronous read synchronous write data memory              (dmem           )
    output  [0:31]  addr_out, // address for fetching data          (.memAddr       )
    input   [0:63]  d_in, // data input from dmem                   (.dataOut       )
    output          memEn, // dmem enable                           (.memEn         )
    output          memWrEn, // dmem write enable                   (.memWrEn       )
    output  [0:63]  dmem_dataOut, // data output to dmem            (.dataIn        )

    // nic                                                          (cardinal_nic   )
    output  [0:63]  din_nic, // data from PE to NIC                 (.d_in          )
    input   [0:1]   addr_nic, // address of registers in the nic    (.addr          )
    output          nicEn, // nic enable                            (.nicEn         )
    output          nicWrEn, // nic write enable                    (.nicWrEn       )
    input   [0:63]  dout_nic // data from NIC to PE                 (.d_out         ) 
//--------------------------------------------------------------------------------------------  

);
    
//-------------------------------------PARAMETERS---------------------------------------------
    // 6-bit OPcode (0-5)
    localparam  R_TYPE_VALU     = 6'b101010; // R-type ALU Ops
    localparam  M_TYPE_VLD      = 6'b100000; // M-type Load
    localparam  M_TYPE_VSD      = 6'b100001; // M-type Store
    localparam  R_TYPE_VBEZ     = 6'b100010; // R-type Branch if Equal to Zero
    localparam  R_TYPE_VBNEZ    = 6'b100011; // R-type Branch if Not Equal to Zero
    localparam  R_TYPE_VNOP     = 6'b111100; // R-type NOP

    // 6-bit ALU OPcode (26-31)
    localparam  VAND            = 6'b000001;
    localparam  VOR             = 6'b000010;
    localparam  VXOR            = 6'b000011;
    localparam  VNOT            = 6'b000100;
    localparam  VMOV            = 6'b000101;
    localparam  VADD            = 6'b000110;
    localparam  VSUB            = 6'b000111;
    localparam  VMULEU          = 6'b001000;
    localparam  VMULOU          = 6'b001001;
    localparam  VSLL            = 6'b001010;
    localparam  VSRL            = 6'b001011;
    localparam  VSRA            = 6'b001100;
    localparam  VRTTH           = 6'b001101;
    localparam  VDIV            = 6'b001110;
    localparam  VMOD            = 6'b001111; 
    localparam  VSQEU           = 6'b010000;
    localparam  VSQOU           = 6'b010001;
    localparam  VSQRT           = 6'b010010;
    localparam  VNOP            = 6'b000000;

    // 3-bit code WW value and odd even
    localparam  DOUBLEWORD      = 3'b000; // 0-63
    localparam  MOSTSWORD       = 3'b001; // 0-31
    localparam  LESTSWORD       = 3'b010; // 32-63
    localparam  EVENBYTES       = 3'b011; // 0-7, 16-23, 32-39, 48-55
    localparam  ODDBYTES        = 3'b100; // 8-15, 24-31, 40-47, 56-63
//--------------------------------------------------------------------------------------------

//--------------------------------------SIGNALS-----------------------------------------------
    // IF stage signals
        reg     [0:31]  pc; // program counter
        // IF/ID stage register
        reg     [0:31]  IF_ID; 

    // ID stage signals
        // stage inputs
        wire    [0:5]   ID_opcode; // 6-bit opcode of Inst.
        wire    [0:4]   ID_rD, ID_rA, ID_rB; // addresses of destination reg D and source reges A, B
        wire    [0:1]   ID_ww; // 2-bit word width
        wire    [0:5]   ID_alu_opcode; // 6-bit alu opcode
        wire    [0:15]  ID_imm_addr; // 16-bit immediate address for M-type Inst.
        // FU signals
        reg             ID_fu_rA, ID_fu_rB;
        // control signals
        wire            stall; // active high; stall signal for every stages
        wire            ID_mem_stall; // For VSD or VLD stall pipeline for 1 clk
        wire            ID_alu_stall5; // For VDIV, VSQRT stall pipeline for 5 clks
        wire            ID_alu_stall4; // For VMULEU, VMULOU, VMOD, VSQEU, VSQOU stall pipeline for 4 clks
        wire            ID_alu_stall3; // For ADD, SUB, SRL, SLL, SRA stall pipeline for 3 clks
        wire            branch_success; // active high; if branch success assert this signal for flush logic
        reg     [0:15]  branch_target; // branch target address
        // Register file signals
        reg             ID_rf_wr_en; // write enable of Register File
        reg     [0:4]   ID_rf_rd_addr_0, ID_rf_rd_addr_1; // address for read port 0 and 1 of Register File
        wire    [0:63]  ID_rf_data_out_0, ID_rf_data_out_1; // data output of read port 0 and 1 of Register File 
        // memory signals
        reg             ID_dmemEn, ID_dmemWrEn; // dmem enable signal, dmem write enable signal 
        reg             ID_nicEn, ID_nicWrEn; // nic enable signal, nic write enable signal
        // forwarding muxes
        reg     [0:63]  ID_data_out_0_mux, ID_data_out_1_mux; 
        // shadow register of dmem
        reg     [0:97]  shadow_reg; // dmemEn + dmemWrEn + {16'b0, imm_addr_id} + ID_data_out_0_mux
        // ID/EXMEM stage register
        reg     [0:154] ID_EXMEM;

    // EXMEM stage signals
        // stage inputs
        wire    [0:4]   EXMEM_rD, EXMEM_rA, EXMEM_rB;
        wire    [0:1]   EXMEM_alu_ww;
        wire    [0:5]   EXMEM_alu_opcode;
        wire    [0:15]  EXMEM_imm_addr;
        wire            EXMEM_dmemEn, EXMEM_dmemWrEn; 
        wire            EXMEM_nicEn, EXMEM_nicWrEn;
        wire    [0:1]   EXMEM_addr_nic
        wire    [0:63]  EXMEM_dout_nic
        wire            EXMEM_rf_wr_en;
            //wire            stall;
        
        // stall signals
        wire            EXMEM_mem_stall; 
        reg             EXMEM_mem_stall_count; // 1-bit counter
        reg             EXMEM_mem_stall_reg; // stall signal for memory accessment
        wire            EXMEM_alu_stall5; 
        reg     [0:2]   EXMEM_alu_stall5_count; // 3-bit counter
        reg             EXMEM_alu_stall5_reg; // stall signal for 5-clk alu operation
        wire            EXMEM_alu_stall4;
        reg     [0:1]   EXMEM_alu_stall4_count; // 2-bit counter
        reg             EXMEM_alu_stall4_reg; // stall signal for 4-clk alu operation
        wire            EXMEM_alu_stall3;
        reg     [0:1]   EXMEM_alu_stall3_count; // 2-bit counter
        reg             EXMEM_alu_stall3_reg; // stall signal for 3-clk alu operation
        
        // alu signals
        wire    [0:63]  EXMEM_alu_source_A, EXMEM_alu_source_B, EXMEM_alu_result;
        //wire    [0:5]   EXMEM_alu_opcode;   
        //wire    [0:1]   EXMEM_alu_ww;
        reg     [0:63]  EXMEM_alu_result_reg;

        // MemToReg MUX
        reg     [0:63]  EXMEM_data_in_mux; // decide data from alu result, dmem, nic, which will be written into RF

        // EXMEM/WB stage register

    // WB stage signals
        wire    [0:63]  WB_rf_data_in; // data input of Register File
        wire            WB_rf_wr_en; // write enbale of Register File
        //wire    [0:2]   WB_rf_ww; // write data word width of Register File
        reg     [0:4]   WB_rf_wr_addr; // address for write port of Register File
        

//--------------------------------------------------------------------------------------------

//--------------------------------SUBMODLUES INSTANTIATION------------------------------------
    // REGISTER FILE INSTANTIATION
    register_file register_file
    (
        .clk        (clk                ), // clock signal
        .reset      (reset              ), // synchronous active high reset
        // Write port signals
        .wr_en      (WB_rf_wr_en        ), // write enable
        .data_in    (WB_rf_data_in      ), // data input
        .wr_ww      (WB_rf_wr_ww        ), // write data word width: Double-Word, Word, Half-Word, Byte
        .wr_addr    (WB_rf_wr_addr      ), // address for write port
        // Read port signals
        .rd_addr_0  (ID_rf_rd_addr_0    ), // address for read port0
        .data_out_0 (ID_rf_data_out_0   ), // data output of read port0 
        .rd_addr_1  (ID_rf_rd_addr_1    ), // address for read port1
        .data_out_1 (ID_rf_data_out_1   ) // data output of read port1
    );

    // ALU INSTANTIATION
    alu alu
    (
        .source_A   (EXMEM_alu_source_A ), // alu source data A
        .source_B   (EXMEM_alu_source_B ), // alu source data B
        .opcode     (EXMEM_alu_opcode   ), // 6-bit alu opcode
        .ww         (EXMEM_alu_ww       ), // word width
        .result     (EXMEM_alu_result   )  // alu result output
    );

//--------------------------------------------------------------------------------------------

//--------------------------------------PIPELINE----------------------------------------------
//-----------------------------------------IF-------------------------------------------------
    // PC logic
    always @(posedge clk) begin
        if (reset == 1'b1) begin // system reset, pc = 0
            pc <= 32'b0;
        end
        else if (stall == 1'b1) begin // pipeline stall, pc stay unchanged
            pc <= pc;
        end
        else if (branch_success == 1'b1) begin // branch success, jump to target
            pc <= {16'b0, branch_target}; // branch_target is 16-bit wide
        else begin
            pc <= pc + 4; // normal cases, pc += 4
        end
    end

    // Inst. fetch
    assign pc_out = pc;

    // Write stage reg IF/ID 
    always @(posedge clk) begin
        if (reset == 1'b1) begin // system reset
            IF_ID <= 0; 
        end 
        else if (stall == 1'b1) begin // pipeline stall, stay unchanged
            IF_ID <= IF_ID;
        end
        else if (branch_success == 1'b1) begin // branch success, flush IF/ID reg
            IF_ID[0:5] <= R_TYPE_VNOP; // inserting bubble to flush
        end
        else begin
            IF_ID <= inst_in; // normal cases, pass the Inst. to ID stage
        end
    end
//--------------------------------------------------------------------------------------------

//-----------------------------------------ID-------------------------------------------------
    // Read stage reg IF/ID, decode Inst.
    assign ID_opcode = IF_ID[0:5];
    assign ID_rD = IF_ID[6:10];
    assign ID_rA = IF_ID[11:15];
    assign ID_rB = IF_ID[16:20];
    assign ID_ww = IF_ID[24:25];
    assign ID_alu_opcode = IF_ID[26:31];
    assign ID_imm_addr = IF_ID[16:31];

    // Generates register file read addresses
    always @(*) begin
        ID_rf_rd_addr_0 = 0;
        ID_rf_rd_addr_1 = 0;
        if (ID_opcode == R_TYPE_VALU) begin // 2 operators inst.
            ID_rf_rd_addr_0 = ID_rA;
            ID_rf_rd_addr_1 = ID_rB;
        end
        if ((ID_opcode == M_TYPE_VSD) || (ID_opcode == R_TYPE_VBEZ) || (ID_opcode == R_TYPE_VBNEZ)) begin // M_TYPE_VLD do not read RF
            ID_rf_rd_addr_0 = ID_rD;
        end
    end

    // mem stall logic
    // For VSD or VLD stall pipeline for 1 clk
    assign ID_mem_stall = ( (ID_opcode == M_TYPE_VSD) 
        || (ID_opcode == M_TYPE_VLD) 
            && (ID_rD != 5'b0) ) ? 1'b1 : 1'b0;

    // alu stall logic
    // For VDIV, VSQRT stall pipeline for 5 clks
    assign ID_alu_stall5 = ( (ID_opcode == R_TYPE_ALU) 
        && ((ID_alu_opcode == VDIV) || (ID_alu_opcode == VSQRT))  
            && (ID_rD != 5'b0) ) ? 1'b1 : 1'b0;

    // For VMULEU, VMULOU, VMOD, VSQEU, VSQOU stall pipeline for 4 clks
    assign ID_alu_stall4 = ( (ID_opcode == R_TYPE_ALU) 
        && ((ID_alu_opcode == VMULEU) || (ID_alu_opcode == VMULOU) || (ID_alu_opcode == VMOD) || (ID_alu_opcode == VSQEU) || (ID_alu_opcode == VSQOU))  
            && (ID_rD != 5'b0) ) ? 1'b1 : 1'b0;

    // For ADD, SUB, SRL, SLL, SRA stall pipeline for 3 clks
    assign ID_alu_stall3 = ( (ID_opcode == R_TYPE_ALU) 
        && ((ID_alu_opcode == VADD) || (ID_alu_opcode == VSUB) || (ID_alu_opcode == VSLL) || (ID_alu_opcode == VSRL) || (ID_alu_opcode == VSRA))  
            && (ID_rD != 5'b0) ) ? 1'b1 : 1'b0;
   
    // Forwarding Unit
    // By comparing the addresses of senior rD and junior rA or rB in ID stage,
    // generates FU signals to forwarding data
    always @(*) begin
        ID_fu_rA = 1'b0;
        ID_fu_rB = 1'b0;
        if ((EXMEM_rf_wr_en == 1'b1) && (EXMEM_rD != 5'b0)) begin // if cpu will write RF and senior rD is not $0
            if (EXMEM_rD == ID_rf_rd_addr_0) begin
                ID_fu_rA = 1'b1;
            end
            if (EXMEM_rD == ID_rf_rd_addr_1) begin
                ID_fu_rB = 1'b1;
            end
        end
    end
    
    // Forwarding logic from EXMEM to ID stage
    // only for R-type inst after finishing alu ops
    always @(*) begin
        ID_data_out_0_mux = ID_rf_data_out_0;
        ID_data_out_1_mux = ID_rf_data_out_1;
        if (ID_fu_rA == 1) begin
            ID_data_out_0_mux = EXMEM_alu_result_reg;
        end
        if (ID_fu_rB == 1) begin
            ID_data_out_1_mux = EXMEM_alu_result_reg;
        end
    end

    // Branch logic 
    always @(*) begin
        // initial values
        branch_success = 1'b0;
        branch_target = ID_imm_addr;

        if ((ID_opcode == R_TYPE_BEZ) && (ID_rD == 5'b0))
            branch_success = 1'b1;
        
        if ((ID_opcode == R_TYPE_BNEZ) && (ID_rD != 5'b0))
            branch_success = 1'b1;
    end

    // Generates dmem and nic control signals 
    always @(*) begin
        // init ctrl signals 
        ID_rf_wr_en = 0;
        ID_dmemEn = 0;
        ID_dmemWrEn = 0;
        ID_nicEn = 0;
        ID_nicWrEn = 0;

        // Asserts ctrl signals value accroding to ints. type
        case (ID_opcode)
            R_TYPE_VALU : begin // alu ops need to write RF 
                ID_rf_wr_en = 1;
            end
            M_TYPE_VLD : begin // loads need to write RF, and read nic or dmem 
                ID_rf_wr_en = 1;
                if (ID_imm_addr[14:15] == 2'b01) begin // read nic input channel status
                    ID_nicEn = 1; 
                end
                else begin // read dmem
                    ID_dmemEn = 1;
                end
            end
            M_TYPE_VSD : begin // stores need to write nic or dmem
                if (ID_imm_addr[14:15] == 2'b11) begin // read nic output channel status
                    ID_nicEn = 1;
                    //ID_nicWrEn = 1;
                end
                else begin // write dmem
                    ID_dmemEn = 1;
                    ID_dmemWrEn = 1;
                end
            end
        endcase
    end

    // shadow register of dmem, when stall happens, dmem could read data from shadow register
    always @(posedge clk) begin
        if (reset == 1'b0) begin
            shadow_reg <= 0;
        end
        else begin 
            if(stall == 1'b1) begin
                shadow_reg <= shadow_reg;
            end
            else
            begin
                shadow_reg[0] <= ID_dmemEn;
                shadow_reg[1] <= ID_dmemWrEn;
                shadow_reg[2:33] <= {16'b0, ID_imm_addr};
                shadow_reg[34:97] <= ID_data_out_0_mux;
            end
        end
    end

    assign memEn = (stall == 1'b1) ? shadow_reg[0] : ID_dmemEn;
    assign memWrEn = (stall == 1'b1) ? shadow_reg[1] : ID_dmemWrEn;
    assign addr_out = (stall == 1'b1) ? shadow_reg[2:33] : {16'b0, ID_imm_addr};
    assign dmem_dataOut = (stall == 1'b1) ? shadow_reg[34:97] : ID_data_out_0_mux;

    
    // Write stage reg ID/EXMEM

    always @(posedge clk) begin
        if (reset == 1'b1) begin // reset
            ID_EXMEM <= 0;
        end
        else begin
            if (stall == 1'b1) begin // stall
                ID_EXMEM <= ID_EXMEM;
            end 
            else begin 
                ID_EXMEM[0:63] <= ID_data_out_0_mux;
                ID_EXMEM[64:127] <= ID_data_out_1_mux;
                ID_EXMEM[128:132] <= ID_rD;
                //ID_EXMEM[133:135] <= ppp_id;
                ID_EXMEM[136:137] <= ID_ww;
                ID_EXMEM[138:143] <= ID_alu_opcode;
                ID_EXMEM[144:145] <= ID_imm_addr[14:15];
                ID_EXMEM[146:150] <= {ID_dmemEn, ID_dmemWrEn, ID_nicEn, ID_nicWrEn, ID_rf_wr_en};
                ID_EXMEM[151] <= ID_mem_stall;
                ID_EXMEM[152] <= ID_alu_stall5;
                ID_EXMEM[153] <= ID_alu_stall4;
                ID_EXMEM[154] <= ID_alu_stall3;
            end
        end
    end 
//--------------------------------------------------------------------------------------------

//----------------------------------------EXMEM-----------------------------------------------
// Read stage reg ID/EXMEM
    assign EXMEM_dout_nic = ID_EXMEM[0:63]; 
    assign {EXMEM_alu_data_in_A, EXMEM_alu_data_in_B} = ID_EXMEM[0:127];
    assign EXMEM_rD = ID_EXMEM[128:132];
    // assign ppp_exm = ID_EXMEM[133:135];
    assign EXMEM_alu_ww = ID_EXMEM[136:137];
    assign EXMEM_alu_opcode = ID_EXMEM[138:143];
    assign EXMEM_addr_nic = ID_EXMEM[144:145]; 
    assign {EXMEM_dmemEn, EXMEM_dmemWrEn, EXMEM_nicEn, EXMEM_nicWrEn, EXMEM_rf_wr_en} = ID_EXMEM[146:150];
    assign EXMEM_mem_stall = ID_EXMEM[151];
    assign EXMEM_alu_stall5 = ID_EXMEM[152];
    assign EXMEM_alu_stall4 = ID_EXMEM[153];
    assign EXMEM_alu_stall3 = ID_EXMEM[154];

// Generates nic signal 
    assign nicEn = EXMEM_nicEn;
    assign nicWrEn = EXMEM_nicWrEn;

// Generates 1-clk memory stall signal
    // couter logic
    always @(posedge clk) begin
        if (reset == 1'b1) begin // init counter
            EXMEM_mem_stall_count <= 0;
        end
        else if (EXMEM_mem_stall == 1'b1) begin // flip counter after use
            EXMEM_mem_stall_count <= ~EXMEM_mem_stall_count;
        end
    end
    // If LD or SD in EX_MEM stage, and counter is 0, generate stall signal for 1 clk
    always @(*) begin
        EXMEM_mem_stall_reg = 1'b0; // init mem stall signal reg
        if ((EXMEM_mem_stall == 1'b1) && (EXMEM_mem_stall_count == 1'b0)) begin
            EXMEM_mem_stall_reg = 1'b1;
        end
    end

// Generates 5-clk alu stall signal
    // couter logic
    always @(posedge clk) begin
        if (reset == 1'b1) begin // init counter
            EXMEM_alu_stall5_count <= 0;
        end
        else if (EXMEM_alu_stall5 == 1'b1) begin 
            if (EXMEM_alu_stall5_count == 3'b100) begin // reset counter after 4
                EXMEM_alu_stall5_count <= 3'b000;
            end
            else begin
                EXMEM_alu_stall5_count <= EXMEM_alu_stall5_count + 1'b1; // increment counter
            end
        end
    end
    // If counter is 0,1,2,3, generate stall signal for 1 more clk
    always @(*) begin
        EXMEM_alu_stall5_reg = 1'b0; // init alu stall5 signal reg
        if ((EXMEM_alu_stall5_count == 3'b000) || (EXMEM_alu_stall5_count == 3'b001) || (EXMEM_alu_stall5_count == 3'b010) || (EXMEM_alu_stall5_count == 3'b011)) begin
            EXMEM_alu_stall5_reg = 1'b1;
        end
    end

// Generates 4-clk alu stall signal
    // couter logic
    always @(posedge clk) begin
        if (reset == 1'b1) begin // init counter
            EXMEM_alu_stall4_count <= 0;
        end
        else if (EXMEM_alu_stall4 == 1'b1) begin 
            if (EXMEM_alu_stall4_count == 2'b11) begin // reset counter after 3
                EXMEM_alu_stall4_count <= 2'b00;
            end
            else begin
                EXMEM_alu_stall4_count <= EXMEM_alu_stall4_count + 1'b1; // increment counter
            end
        end
    end
    // If counter is 0,1,2, generate stall signal for 1 more clk
    always @(*) begin
        EXMEM_alu_stall4_reg = 1'b0; // init alu stall4 signal reg
        if ((EXMEM_alu_stall4_count == 2'b00) || (EXMEM_alu_stall4_count == 2'b01) || (EXMEM_alu_stall4_count == 2'b10)) begin
            EXMEM_alu_stall4_reg = 1'b1;
        end
    end

// Generates 3-clk alu stall signal
    // couter logic
    always @(posedge clk) begin
        if (reset == 1'b1) begin // init counter
            EXMEM_alu_stall3_count <= 0;
        end
        else if (EXMEM_alu_stall3 == 1'b1) begin 
            if (EXMEM_alu_stall3_count == 2'b10) begin // reset counter after 2
                EXMEM_alu_stall3_count <= 2'b00;
            end
            else begin
                EXMEM_alu_stall3_count <= EXMEM_alu_stall3_count + 1'b1; // increment counter
            end
        end
    end
    // If counter is 0,1, generate stall signal for 1 more clk
    always @(*) begin
        EXMEM_mem_stall_reg = 1'b0; // init mem stall signal reg
        if ((EXMEM_alu_stall3_count == 2'b00) || (EXMEM_alu_stall3_count == 2'b01)) begin
            EXMEM_alu_stall3_reg = 1'b1;
        end
    end

    assign stall = (EXMEM_mem_stall_reg || EXMEM_alu_stall5_reg || EXMEM_alu_stall4_reg || EXMEM_alu_stall2_reg) ? 1'b1 : 1'b0;

// Mem to Reg MUX logic  
    // data from alu result, dmem, nic
    always @(*)
    begin
        EXMEM_data_in_mux = EXMEM_alu_result; // data from alu 
        if (EXMEM_dmemEn == 1'b1) begin
            EXMEM_data_in_mux = d_in[0:63]; // data from dmem
        end
        else if (EXMEM_nicEn == 1'b1) begin
            EXMEM_data_in_mux = dout_nic[0:63]; // data from nic
        end
    end

// Write stage reg EXMEM/WB
    reg [0:72] EXMEM_WB;
    always @(posedge clk) begin
        if(reset == 1'b1) begin // system reset
            EXMEM_WB <= 0;
        end
        else if(stall == 1'b1) begin
            EXMEM_WB[64] <= 0; // pipeline stall, insert bubble to WB
        end
        else begin
            EXMEM_WB[0:63] <= EXMEM_data_in_mux[0:63];
            EXMEM_WB[64] <= EXMEM_rf_wr_en;
            //EXMEM_WB[65:67] <= ppp_exm;
            EXMEM_WB[68:72] <= EXMEM_rD;
        end
    end

//--------------------------------------------------------------------------------------------

//------------------------------------------WB------------------------------------------------
// Read stage reg EXMEM/WB
    assign WB_rf_data_in = EXMEM_WB[0:63];
    assign WB_rf_wr_en = EXMEM_WB[64];
    //assign ppp_wb = EXMEM_WB[65:67];
    assign WB_rf_wr_addr = EXMEM_WB[68:72];
    
//--------------------------------------------------------------------------------------------

endmodule
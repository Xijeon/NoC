/*
 * @Name         : cardinal_cpu
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-25 11:17:56
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-31 22:00:52
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
    input   [0:63]  din_nic, // data from PE to the nic             (.d_in          )
    input   [0:1]   addr_nic, // address of registers in the nic    (.addr          )
    output          nicEn, // nic enable                            (.nicEn         )
    output          nicWrEn, // nic write enable                    (.nicWrEn       )
    output  [0:63]  dout_nic // data from nic to PE                 (.d_out         ) 
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
        reg     [0:31]  IF_ID; // IF/ID stage register

    // ID stage signals
        // control signals
        wire            stall; // active high; declared as wire, as we intend to produce it using a continuous assign statement
        wire            branch_success; // active high; if branch success assert this signal for flush logic
        reg     [0:31]  branch_target; // branch target address
        // Register file signals
        reg             ID_rf_wr_en; // write enable of Register File
        reg     [0:4]   ID_rf_rd_addr_0, ID_rf_rd_addr_1; // address for read port 0 and 1 of Register File
        wire    [0:63]  ID_rf_data_out_0, ID_rf_data_out_1; // data output of read port 0 and 1 of Register File 
        // decode inst.
        wire    [0:5]   ID_opcode; // 6-bit opcode of Inst.
        wire    [0:4]   ID_rD, ID_rA, ID_rB; // addresses of destination reg D and source reges A, B
        wire    [0:1]   ID_ww; // 2-bit word width
        wire    [0:5]   ID_alu_opcode; // 6-bit alu opcode
        wire    [0:15]  ID_imm_addr; // 16-bit immediate address for M-type Inst.
        // external signals
        reg             ID_dmemEn, ID_dmemWrEn; // dmem enable signal, dmem write enable signal 
        reg             ID_nicEn, ID_nicWrEn; // nic enable signal, nic write enable signal

    // EXMEM stage signals

    // WB stage signals
    wire            WB_rf_wrEn; // write enbale of Register File
    wire    [0:2]   WB_rf_wrWw; // write data word width of Register File
    reg     [0:4]   WB_rf_wr_addr; // address for write port of Register File
    wire    [0:63]  WB_rf_data_in; // data input of Register File

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
        .data_in_A  (EXMEM_alu_data_in_A), // alu data A
        .data_in_B  (EXMEM_alu_data_in_B), // alu data B
        .opcode     (EXMEM_alu_opcode   ), // 6-bit alu opcode
        .wrWw       (EXMEM_alu_wrWw     ), // word width
        .data_out   (EXMEM_alu_data_out )  // alu data output
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
            pc <= branch_target;
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

    // stall logic
    // If there is a SD or a LD (rD is not $0), we have the intent to stall in next stage
    // this signal is used to control the stall flag register
    wire intent_to_stall_id;
    assign intent_to_stall_id = ((opcode_id == M_TYPE_SD) || ((opcode_id == M_TYPE_LD) && (rD_id != 0)));

    // Intention for 5-clock ALU stall
    // For DIV, SQRT,
    wire intent_to_alu_stall5_id;
    assign intent_to_alu_stall5_id = ( (opcode_id == R_TYPE_ALU) && ((func_code_id == VDIV) || (func_code_id == VSQRT))  && (rD_id != 0) ) ? 1'b1 : 1'b0;

    // Intention for 4-clock ALU stall
    // For MULT, SQ, MOD, 
    wire intent_to_alu_stall4_id;
    assign intent_to_alu_stall4_id = ( (opcode_id == R_TYPE_ALU) 
        && ((func_code_id == VMULEU) || (func_code_id == VMULOU) || (func_code_id == VMOD) || (func_code_id == VSQEU) || (func_code_id == VSQOU))  
            && (rD_id != 0) ) ? 1'b1 : 1'b0;

    // Intention for 3-clock ALU stall
    // For ADD, SUB, SRL, SLL, SRA 
    wire intent_to_alu_stall3_id;
    assign intent_to_alu_stall3_id = ( (opcode_id == R_TYPE_ALU) 
        && ((func_code_id == VADD) || (func_code_id == VSUB) || (func_code_id == VSLL) || (func_code_id == VSRL) || (func_code_id == VSRA))  
            && (rD_id != 0) ) ? 1'b1 : 1'b0;

    // Generates register file read address of port 0 and port 1
    always @(*)
    begin
        RF_rd_addr_1 = rB_id;
        
        if((opcode_id == M_TYPE_SD) || (opcode_id == R_TYPE_BEZ) || (opcode_id == R_TYPE_BNEZ))
            RF_rd_addr_0 = rD_id;
        else
            RF_rd_addr_0 = rA_id;
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
                if (ID_imm_addr == 2'b01) begin // read nic input channel status
                    ID_nicEn = 1; 
                end
                else begin // read dmem
                    ID_dmemEn = 1;
                end
            end
            M_TYPE_VSD : begin // stores need to write nic or dmem
                if (ID_imm_addr == 2'b11) begin // read nic output channel status
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


    

//--------------------------------------------------------------------------------------------







//----------------------------------------EXMEM-----------------------------------------------
//--------------------------------------------------------------------------------------------

//------------------------------------------WB------------------------------------------------
//--------------------------------------------------------------------------------------------
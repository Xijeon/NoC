/*
 * @Name         : register_file
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-24 18:17:33
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-31 21:00:03
 * @Description  : 
                The Register File is a 3-ported (2-READ port and 1-WRITE port) general purpose register 
                file that implements 32 64-bit registers. The reading from register-file is asynchronous 
                while writing to register file is synchronous. Each port consists of 5-bit address (address specifier) 
                and a 64-bit data for reading/writing the contents to the specified register. 
                
                At reset, all register contents must be cleared. Register0 needs to be hard-wired to
                64'h0000_0000_0000_0000 and is READ ONLY, i.e. register0 location cannot be written to. 
                
                Lastly, the write port should also contain a write enable signal (wr_en) to control write 
                operation of the register file. The read ports do not have enable signals, so each read-port 
                will read the register contents based on the associated 5-bit address presented (asynchronously).
 */

module register_file (
    // RF control signals
    input               clk, // clock signal
    input               reset, // synchronous active high reset

    // Write port signals
    input               wr_en, // write enable
    input [0:63]        data_in, // data input
    input [0:2]         wr_ww, // write data word width: Double-Word, Word, Half-Word, Byte
    input [0:4]         wr_addr, // address for write port, at where to write data in

    // Read port signals
    input [0:4]         rd_addr_0, // address for read port0, from where to read data out 
    output reg [0:63]   data_out_0, // data output of read port0
    input [0:4]         rd_addr_1, // address for read port1, from where to read data out
    output reg [0:63]   data_out_1 // data output of read port1
);

    //--------------------------------------------------------------------------------------------
    // WW value and odd even
    localparam  DOUBLEWORD  = 3'b000; // 0-63
    localparam  MOSTSWORD   = 3'b001; // 0-31
    localparam  LESTSWORD   = 3'b010; // 32-63
    localparam  EVENBYTES   = 3'b011; // 0-7, 16-23, 32-39, 48-55
    localparam  ODDBYTES    = 3'b100; // 8-15, 24-31, 40-47, 56-63

    //--------------------------------------------------------------------------------------------
    // Implement regiseter array
    reg [0:63] register[1:31]; // register file 64x32
    //assign register[0] = {63{1'b0}}; latch, do not implement register[0]

    //--------------------------------------------------------------------------------------------
    // Writing logic  synchronous
    always @(posedge clk) begin : synchronous_write
        reg [0:5] i;
        if (reset == 1'b1) begin // reset, all regs are set 64'b0
            for (i = 1; i < 32; i = i + 1) begin
                register[i] <= 64'b0;
            end
        end
        else begin // reset == 1'b0
            if ((wr_en == 1'b1) && (wr_addr != 1'b0)) begin // write enable = 1'b1 and address is not register[0]
                case(wr_ww)
                    DOUBLEWORD : // write 0-63
                        register[wr_addr] <= data_in;
                    MOSTSWORD : // write 0-31
                        register[wr_addr][0:31] <= data_in[0:31];
                    LESTSWORD : // write 32-63
                        register[wr_addr][32:63] <= data_in[32:63];
                    EVENBYTES : begin // write 0-7, 16-23, 32-39, 48-55
                        register[wr_addr][0:7] <= data_in[0:7];
                        register[wr_addr][16:23] <= data_in[16:23];
                        register[wr_addr][32:39] <= data_in[32:39];
                        register[wr_addr][48:55] <= data_in[48:55];
                    end
                    ODDBYTES : begin // write 8-15, 24-31, 40-47, 56-63
                        register[wr_addr][8:15] <= data_in[8:15];
                        register[wr_addr][24:31] <= data_in[24:31];
                        register[wr_addr][40:47] <= data_in[40:47];
                        register[wr_addr][56:63] <= data_in[56:63];
                    end
                endcase
            end
        end
    end 
    //--------------------------------------------------------------------------------------------

    //--------------------------------------------------------------------------------------------
    // Reading logic  asynchronous
    always @(*) begin : asynchronous_read
        //--------------------------------------------------------------------------------------------
        // read port 0
        if (rd_addr_0 == 5'b00000) begin // if read register[0], value is 64'b0
            data_out_0[0:63] = 64'b0;
        end
        else begin // if read other registers, using rd_addr_0 index to that register
            data_out_0[0:63] = register[rd_addr_0];
        end

        //--------------------------------------------------------------------------------------------
        // read port 1
        if (rd_addr_1 == 5'b00000) begin // if read register[0], value is 64'b0
            data_out_1[0:63] = 64'b0;
        end
        else begin // if read other registers, using rd_addr_0 index to that register
            data_out_1[0:63] = register[rd_addr_1];
        end
    end
    //--------------------------------------------------------------------------------------------
endmodule
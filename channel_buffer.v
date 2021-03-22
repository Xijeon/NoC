/*
 * @Name         : channel_buffer
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-18 23:26:28
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-21 20:50:59
 * @Description  : buffer in routers and nic, one-entry synchronous fifo buffer using common clk for write and read
 */

module channel_buffer #(
    parameter DATA_WIDTH = 64 // define data width
)(
    input clk, reset, // clock, synchronous hign active reset
    input re, we, // read enable and write enable
    input [DATA_WIDTH-1:0] data_in, // data input
    output [DATA_WIDTH-1:0] data_out, // data output
    output full, empty // fifo buffer full and empty signal for output
);
   
    reg [DATA_WIDTH-1:0] entry; // the entry, data storage
    reg full_empty; // singal used to represent empty(0) or full(1)
    wire re_q, we_q; //  write enable qualified and read enable qualified

    // buffer full empty logic
    assign full = full_empty; 
    assign empty = ~full_empty;

    // read write enable qualified logic
    assign re_q = (re & full_empty);
    assign we_q = (we & (!full_empty));

    // clk-controled fifo logic
    always @(posedge clk) begin
        if (reset == 1'b1) begin // reset logic, fifo is empty, clear fifo entry 
            full_empty <= 0;
            entry <= 0;
        end
        else begin // fifo logic
            if (re_q == 1'b1) begin // when read enable is qualified, data will be read out, after this clk cycle
                full_empty <= 0; // fifo will be empty, after this clk cycle
            end
            else if (we_q == 1'b1) begin // when write enable is qualified, data will be writen in
                entry <= data_in; // data will be writen in fifo, after this clk cycle
                full_empty <= 1; // fifo will be full, after this clk cycle
            end
        end
    end
    
    // data output logic
    assign data_out = entry;
    
endmodule
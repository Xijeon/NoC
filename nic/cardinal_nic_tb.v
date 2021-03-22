/*
 * @Name         : cardinal_nic_tb
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-20 15:55:41
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-22 16:21:10
 * @Description  : for cardinal_nic functional testing 
                  reset 0-2clk
                  router side test 
                  processor side test
 */

`timescale 1ns/10ps
module tb;

    //Parameters
    parameter DATA_WIDTH = 64; // 64-bit pkt 
    parameter CLK_CYCLE = 4; // 4n clk cycle 
    
    // Processor side signals
    reg [0:1] addr;
    reg [0:DATA_WIDTH-1] d_in;
    wire [0:DATA_WIDTH-1] d_out;
    reg nicEn;
    reg nicEnWr;

    // Router side signals
    reg net_si;
    wire net_ri;
    reg [0:DATA_WIDTH-1] net_di;
    wire net_so;
    reg net_ro;
    wire [0:DATA_WIDTH-1] net_do;
    reg net_polarity;
    
    // Control signals
    reg clk;
    reg reset;


    // Setting cardinal_nic module as dut
    cardinal_nic #(.DATA_WIDTH(DATA_WIDTH))
        cardinal_nic_dut
        (
            .clk            (clk            ),
            .reset          (reset          ),
            .net_so         (net_so         ),
            .net_ro         (net_ro         ),
            .net_do         (net_do         ),
            .net_polarity   (net_polarity   ),
            .net_si         (net_si         ),
            .net_ri         (net_ri         ),
            .net_di         (net_di         ),
            .addr           (addr           ),
            .d_in           (d_in           ),
            .d_out          (d_out          ),
            .nicEn          (nicEn          ),
            .nicEnWr        (nicEnWr        )
        );

    // Generating 4ns clock
    always begin
        #(0.5 * CLK_CYCLE) clk = ~clk;
    end
    
    // Generating net_polarity signal
    always @(posedge clk) begin
        if (reset == 1) begin
            net_polarity <= 0;
        end
        else begin
            net_polarity <= ~net_polarity;
        end
    end


    initial begin
        // Initializing control signals
        clk = 0;
        reset = 1;

        nicEn = 1; // NIC always enabled
        nicEnWr = 0;

        net_ro = 0;
        net_si = 0;

        // Reset
        #(1.5 * CLK_CYCLE); // assert reset = 1, last 1.5 cycles
        reset = 0;
        #(0.5 * CLK_CYCLE);
    //--------------------------------------------------------------------------------------------
        // nic router hand shake test
        // write data in output buffer
        #(0.1 * CLK_CYCLE);
        addr = 2'b11; // get output buffer status
        #(0.1 * CLK_CYCLE);
        if (d_out[63] == 0) begin // check if output buffer is empty
            addr = 2'b10;
            nicEnWr = 1;
            d_in[0:DATA_WIDTH-1] = 64'h0000_1111_0000_1111;
        end
        #(0.8 * CLK_CYCLE);
        nicEnWr = 0;
        // router read data 
        #(0.5 * CLK_CYCLE);
        net_ro = 1;
        #(2 * CLK_CYCLE);
        net_ro = 0;

        // blocking 5 clk
        #(4.5 * CLK_CYCLE);

        // write data in output buffer
        #(0.1 * CLK_CYCLE);
        addr = 2'b11; // get output buffer status
        #(0.1 * CLK_CYCLE);
        if (d_out[63] == 0) begin // check if output buffer is empty
            addr = 2'b10;
            nicEnWr = 1;
            d_in[0:DATA_WIDTH-1] = 64'hF000_1111_0000_2222;
        end
        #(0.8 * CLK_CYCLE);
        nicEnWr = 0;
        // router read data 
        #(0.5 * CLK_CYCLE);
        net_ro = 1;
        #(2 * CLK_CYCLE);
        net_ro = 0;

    end

    initial begin
        #(15 * CLK_CYCLE);
        // Initializing control signals
        clk = 0;
        reset = 1;

        nicEn = 1; // NIC always enabled
        nicEnWr = 0;

        net_ro = 0;
        net_si = 0;

        // Reset
        #(1.5 * CLK_CYCLE); // assert reset = 1, last 1.5 cycles
        reset = 0;
        #(0.5 * CLK_CYCLE);
    //--------------------------------------------------------------------------------------------
        // nic processor read/write test
        // store data in NIC, output buffer is available
        #(0.1 * CLK_CYCLE);
        addr = 2'b11; // get output buffer status
        #(0.1 * CLK_CYCLE);
        if (d_out[63] == 0) begin // check if output buffer is empty
            addr = 2'b10;
            nicEnWr = 1;
            d_in[0:DATA_WIDTH-1] = 64'h0000_0000_0000_1111;
        end
        #(0.8 * CLK_CYCLE);
        nicEnWr = 0;
        #(CLK_CYCLE);

        // store data in NIC, output buffer is unavailable
        #(0.1 * CLK_CYCLE);
        addr = 2'b11; // get output buffer status
        #(0.1 * CLK_CYCLE);
        if (d_out[63] == 0) begin // check if output buffer is empty
            addr = 2'b10;
            nicEnWr = 1;
            d_in[0:DATA_WIDTH-1] = 64'hF000_0000_0000_2222;
        end
        #(0.8 * CLK_CYCLE);
        nicEnWr = 0;
        #(CLK_CYCLE);
        
        // load data in NIC, input buffer is available
        // input data in NIC from router
        if (net_ri == 1) begin
            #(0.1 * CLK_CYCLE)
            net_si = 1;
            net_di[0:DATA_WIDTH-1] = 64'hF000_1010_0000_1111;
            #(CLK_CYCLE)
            net_si = 0;
        end
        #(CLK_CYCLE)
        // load this data
        addr = 2'b01; // fetch d_out[63](input buffer status reg)
        #(0.1 * CLK_CYCLE) 
        if(d_out[63] == 1) //check the status reg of input buffer
        begin
            addr = 2'b00; // load data
        end
        #(0.9 * CLK_CYCLE);
        #(CLK_CYCLE);

        // load data in NIC, input buffer is unavailable
        // do not input data in NIC

        // load data, but input buffer is empty
        addr = 2'b01; // fetch d_out[63](input buffer status reg)
        #(0.1 * CLK_CYCLE) 
        if(d_out[63] == 1) //check the status reg of input buffer
        begin
            addr = 2'b00; // load data
        end
        #(0.9 * CLK_CYCLE);
        #(CLK_CYCLE);
        $finish;
    end
    
endmodule
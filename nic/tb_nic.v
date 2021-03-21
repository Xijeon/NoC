/*
 * @Name         : cardinal_nic_tb
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-20 15:55:41
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-20 22:53:32
 * @Description  : for cardinal_nic functional testing 
 */

`timescale 1ns/10ps
module cardinal_nic_tb;

    //Parameters
    parameter DATA_WIDTH = 64; // 64-bit pkt 
    parameter CLK_CYCLE = 4; // 4n clk cycle 
    
    // Processor side signals
    reg [1:0] addr;
    reg [DATA_WIDTH-1:0] d_in;
    wire [DATA_WIDTH-1:0] d_out;
    reg nicEn;
    reg nicEnWr;

    // Router side signals
    reg net_si;
    wire net_ri;
    reg [DATA_WIDTH-1:0] net_di;
    wire net_so;
    reg net_ro;
    wire [DATA_WIDTH-1:0] net_do;
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
        if (reset) begin
            net_polarity <= 0;
        end
        else begin
            net_polarity <= ~net_polarity;
        end
    end

    // Display data recived from both side in txt files
    integer processor_data, router_data; // data recived from processor, data recived from router
    initial
    begin
        processor_data = $fopen("processor_data.txt", "w");
        router_data = $fopen("router_data.txt", "w");
    end

    // a flag used to indicate if data sending from router finished
    // if send_finish == 1, data sending from processor started
    reg send_finish; 
    initial begin : 
        // Initializing control signals
        clk = 0;
        reset = 1;

        nicEn = 1; // NIC always enabled
        nicEnWr = 0;

        net_ro = 0;
        net_si = 0;

        send_finish = 0;

        #(4 * CLK_CYCLE) // assert reset = 1, 4 cycles
        reset = 0;

        // Router send data to NIC
        integer i;
        for (i = 0; i < 10; i = i + 1) begin
            wait(net_ri == 1) // Router wait for NIC is ready for receive data
            #(0.2 * CLK_CYCLE) // After 0.2clk Router send data to NIC
            net_si = 1;
            net_di[63:0] = 64'h1;
            #(CLK_CYCLE)
            net_si = 0; // Next clk Router 
        end

        #(10 * CLK_CYCLE);
        send_finish = 1; // change flag
        #(10 * CLK_CYCLE);

        // sending data from processor side
        i = 0;
        while (i < 10) begin
            #(0.2 * CLK_CYCLE)
            addr = 2'b11;
            #(0.2 * CLK_CYCLE)

            if (d_out[63] == 0) begin// checking status reg of output buffer
            
                addr = 2'b10;
                nicEnWr = 1;
                d_in = i;
                d_in[0] = i % 2; // change the vc bit to test conditional sending to router
                i = i + 1;
            end
            #(0.8 * CLK_CYCLE)
            nicEnWr = 0;
        end
        
        #(10 * CLK_CYCLE)
        $fclose(data_received_pe | data_received_router);
        $finish;
    end

initial begin
    #1;
        oprA[31:0] = 32'b0; 
        oprB[31:0] = 32'b0;
    end

    // scan data input pattern
    integer processor_sent_data, router_sent_data; // data sent by processor, data sent by router
    integer scan_p, scan_r; // scan input data file
    initial begin
        processor_sent_data = $fopen("processor_sent_data.txt", "r");
        router_sent_data = $fopen("router_sent_data.txt", "r");
    end

    always begin
        #5;
        if (!$feof(processor_sent_data)) begin
            scan_p = $fscanf(processor_sent_data, "%h\n", d_in);
        end
        else begin
            $finish;
            $fclose(processor_sent_data);
        end

        if (!$feof(router_sent_data)) begin
            scan_r = $fscanf(router_sent_data, "%h\n", net_di);
        end
        else begin
            $finish;
            $fclose(router_sent_data);
        end
    end



    // Reveiving data at processor side
    initial 
    begin : loop_1
        #(3.5 * CLK_CYCLE)
        forever 
        begin 
        
            if (send_finish == 1)
                disable loop_1; // if data sending from router finished, disable this block

            addr = 2'b01;
            #(0.2 * CLK_CYCLE) 

            if (d_out[63] == 1) begin //check the status reg of input buffer
                addr = 2'b00;
                #(0.2 * CLK_CYCLE)
                $fdisplay(data_received_pe, "%1d", d_out[32:63]);
            end
            else #(0.2 * CLK_CYCLE);

            #(0.8 * CLK_CYCLE);
        end
    end

    //Receiving data from router side
    initial
    begin
        #(3.5 * CLK_CYCLE)
        forever @(posedge clk)
        begin
            net_ro = 1;
            #(0.2 * CLK_CYCLE)
            if(net_so == 1)
                $fdisplay(data_received_router, "%1d", net_do[32:63]);
        end
    end

 endmodule
/*
 * @Name         : cardinal_nic
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-18 22:59:15
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-19 17:33:19
 * @Description  : 
    The Network Interface Component (NIC) to be implemented to provide a path from the processor to the underlying
    ring network is a two-register interface, which is simple yet efficient. On the sender side, packets are sent via a
    single network output channel buffer in the NIC, to which the outgoing packets are written. On the receiver side,
    packets are received via a single network input channel buffer in the NIC, from which the incoming packets
    are read. The network input and output channel buffers as well as their status registers are memory address mapped. 
    Thus, processors can access them using regular store/load instructions. As a result, the NIC provides the 
    processors with an interface very much the same as the memory interface so that the processors need not
    to deal with the details in the network (e.g., handshaking signaling and polarity, among others). 
 */
module cardinal_nic #(
    parameter DATA_WIDTH = 64 // Packet data length
)(
//------------------------------PORTS---------------------------------------------------------
    // Processor side signals
    input [1:0] addr, // Specify the memory address mapped registers in the NIC.
    input [DATA_WIDTH-1:0] d_in, // Input packet from the PE to be injected into the network.
    output reg [DATA_WIDTH-1:0] d_out, // Content of the register specified by addr[1:0].
    input nicEn, // Enable signal to the NIC. If not asserted, d_out port assumes 64'h0000_0000.
    input nicEnWr, // Write enable signal to the NIC. If asserted along with nicEn , the data on the d_in port is written into the network output channel.

    // Router side signals
    input net_si, // Send handshaking signal for the network input channel.
    output reg net_ri, // Ready handshaking signal for the network input channel.
    input [DATA_WIDTH-1:0] net_di, // Packet data for the network input channel.
    output reg net_so, // Send handshaking signal for the network output channel.
    input net_ro, // Ready handshaking signal for the network output channel.
    output reg [DATA_WIDTH-1:0] net_do, // Packet data for the network output channel.
    input net_polarity // Polarity input from the router connected to the NIC.

    // Control signals
    input clk, // Clock signal.
    input reset, // Reset signal. Reset is synchronous and asserted high.
//--------------------------------------------------------------------------------------------
);

//------------------------------INNER SIGNALS-------------------------------------------------
    // Inner control signals for buffers
    reg in_buffer_re, out_buffer_re; // read enable signal for both buffers
    reg in_buffer_we, out_buffer_we; // write enable signal for both buffers
    reg [DATA_WIDTH-1:0] in_buffer_di, out_buffer_di; // data in for both buffers
    wire [DATA_WIDTH-1:0] in_buffer_do, out_buffer_do; // data out for both buffers
    reg in_buffer_status, // status register of input channel buffer
    reg out_buffer_status; // status register of output channel buffer
//--------------------------------------------------------------------------------------------

//------------------------------TWO CHANNEL BUFFERS-------------------------------------------
    // input channel buffer
    channel_buffer #(.DATA_WIDTH(DATA_WIDTH)) 
        in_buffer (
            .clk        (clk                ), 
            .reset      (reset              ),
            .re         (in_buffer_re       ), 
            .we         (in_buffer_we       ), 
            .data_in    (in_buffer_di       ), 
            .data_out   (in_buffer_do       ), 
            .full       (in_buffer_status   ), // the full signal register of input channel buffer
            .empty      ()// do not care input buffer is empty or not
    );

    // output channel buffer
    channel_buffer #(.DATA_WIDTH(DATA_WIDTH)) 
        out_buffer (
            .clk        (clk                ), 
            .reset      (reset              ),
            .re         (out_buffer_re      ), 
            .we         (out_buffer_we      ), 
            .data_in    (out_buffer_di      ), 
            .data_out   (out_buffer_do      ), 
            .full       (), // do not care output buffer is full or not
            .empty      (out_buffer_status  ) // the empty signal register of output channel buffer
    );
//--------------------------------------------------------------------------------------------

//------------------------------LOGICS OF NIC-------------------------------------------------
    //---------------------------------------RESET--------------------------------------------
    always @(posedge clk) begin
        if (reset == 1'b0) begin
            in_buffer_status = 1'b0;
            out_buffer_status = 1'b0;

            // router
            net_so = 1'b0;
            out_buffer_we = 1'b0;
            in_buffer_re = 1'b0;

            // processor
            d_out = 64'h0000_0000; // If not asserted, d_out port assumes 64'h0000_0000
        end
    end
    //----------------------------------------------------------------------------------------

    //----------------------------HAND SHAKING WITH THE ROUTER--------------------------------
    // data_in from router
    always @(*) begin
        in_buffer_di = net_di; // data input from router

        if(in_buffer_status == 1'b0) begin // if input buffer is empty, tell router input channel is ready
            net_ri = 1'b1;
        end
        else begin // if input buffer is full, tell router input channel is not ready
            net_ri = 1'b0;
        end

        if((in_buffer_status == 1'b0) && (net_si == 1'b1)) begin // if input buffer is empty and router want to write data in
            in_buffer_we = 1'b1; // then write new data into input buffer
        end
        else begin // if input buffer is empty and router want to write data in
            in_buf_we = 1'b0; // 
        end
    end
    
    // data_out from NIC
    always @(*) begin
        net_do = out_buffer_do;
        //net_so = 1'b0;

        if((out_buffer_status == 1'b1) && (net_ro == 1'b1))
        begin
            // when polarity == 1, even virtual channel is used externally
            // only packet with vc = 0 can enter virtual channel 0, vice versa
            if((net_polarity == 1'b1)  && (out_buffer_do[0] == 1'b0)) // note: bit 0 is VC bit
                net_so = 1'b1;
            if((net_polarity == 1'b0) && (out_buffer_do[0] == 1'b1))
                net_so = 1'b1;
        end

        if((net_so == 1'b1) && (net_ro == 1'b1)) out_buffer_re = 1'b1;
        else out_buffer_re = 1'b0;
    end
    //----------------------------------------------------------------------------------------

    //------------------------------INTERFACING WITH PROCESSOR--------------------------------
    always @(*) begin
        // set initial value
        //out_buffer_we = 1'b0;
        //in_buffer_re = 1'b0;
        //d_out = 64'h0000_0000; // If not asserted, d_out port assumes 64'h0000_0000
    
        // NIC reg address logic
        out_buffer_di = d_in; // data input from processor
        
        if (nicEn == 1'b1) begin 
            if (nicEnWr == 1'b1) begin 
                if (addr == 2'b10) begin // nicEn == 1, nicEnWr == 1, addr == 10, write data_in into output buffer at next clk
                    out_buffer_we = 1'b1;
                end
            end
            else begin // nicEn == 1, nicEnWr == 0
                case(addr)
                    2'b00 : begin // addr == 00, read out data in input buffer at next clk
                        in_buffer_re = 1'b1;
                        d_out = in_buffer_do;
                    end
                    2'b01 : begin // addr == 01, read status register of input channel buffer
                        d_out[63] = in_buffer_status;
                    end
                    2'b11 : begin // addr == 11, read status register of output channel buffer
                        d_out[63] = out_buffer_status;
                    end
                endcase
            end
        end
    end
    //----------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------
    
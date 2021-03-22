/*
 * @Name         : cardinal_nic
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-18 22:59:15
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-22 15:47:26
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
    input [0:1] addr, // Specify the memory address mapped registers in the NIC.
    input [0:DATA_WIDTH-1] d_in, // Input packet from the PE to be injected into the network.
    output reg [0:DATA_WIDTH-1] d_out, // Content of the register specified by addr[1:0].
    input nicEn, // Enable signal to the NIC. If not asserted, d_out port assumes 64'h0000_0000.
    input nicEnWr, // Write enable signal to the NIC. If asserted along with nicEn , the data on the d_in port is written into the network output channel.

    // Router side signals
    input net_si, // Send handshaking signal for the network input channel.
    output reg net_ri, // Ready handshaking signal for the network input channel.
    input [0:DATA_WIDTH-1] net_di, // Packet data for the network input channel.
    output reg net_so, // Send handshaking signal for the network output channel.
    input net_ro, // Ready handshaking signal for the network output channel.
    output reg [0:DATA_WIDTH-1] net_do, // Packet data for the network output channel.
    input net_polarity, // Polarity input from the router connected to the NIC.

    // Control signals
    input clk, // Clock signal.
    input reset // Reset signal. Reset is synchronous and asserted high.
//--------------------------------------------------------------------------------------------
);

//------------------------------INNER SIGNALS-------------------------------------------------
    // Inner control signals for buffers
    reg in_buffer_re, out_buffer_re; // read enable signal for both buffers
    reg in_buffer_we, out_buffer_we; // write enable signal for both buffers
    reg [0:DATA_WIDTH-1] in_buffer_di, out_buffer_di; // data in for both buffers
    wire [0:DATA_WIDTH-1] in_buffer_do, out_buffer_do; // data out for both buffers
    wire in_buffer_status; // status register signal of input channel buffer
    wire out_buffer_status; // status register signal of output channel buffer
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
            .empty      ()
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
            .full       (out_buffer_status  ), // the full signal register of output channel buffer
            .empty      ()
    );
//--------------------------------------------------------------------------------------------

//------------------------------LOGICS OF NIC-------------------------------------------------
    //---------------------------------------RESET--------------------------------------------
    always @(posedge clk) begin
        if (reset == 1'b0) begin
            //in_buffer_status = 1'b0;
            //out_buffer_status = 1'b0;

            // router
            //net_so = 1'b0;
            out_buffer_we = 1'b0;
            in_buffer_re = 1'b0;

            // processor
            //d_out = 64'h0; // If not asserted, d_out port assumes 64'h0
        end
    end
    //----------------------------------------------------------------------------------------

    //----------------------------HAND SHAKING WITH THE ROUTER--------------------------------
    // data_in from router
    always @(*) begin
        in_buffer_di = net_di; // data input from router to NIC

        if(in_buffer_status == 1'b0) begin // if input buffer is empty, tell router input channel is ready
            net_ri = 1'b1;
        end
        else begin // if input buffer is full, tell router input channel is not ready
            net_ri = 1'b0;
        end

        if((in_buffer_status == 1'b0) && (net_si == 1'b1)) begin // if input buffer is empty and router ready to write data in,
            in_buffer_we = 1'b1; // allow writing new data into input buffer
        end
        else begin // if input buffer is full,
            in_buffer_we = 1'b0; // prohibit writing new data into input buffer
        end
    end
    
    // data_out from NIC
    always @(*) begin
        net_do = 64'h0; // data output from NIC to router
        net_so = 1'b0; // reset net_so to 0 after change channel polarity

        if ((out_buffer_status == 1'b1) && (net_ro == 1'b1)) begin // if out buffer is full and router is ready to read data out, check polarity
        // For an odd polarity clk cycle:
        // Even output virtual channel buffer is forwarded to corresponding even input virtual channel buffer of next router if conditions allow 
        // Vice versa
            if ((net_polarity == 1'b1) && (out_buffer_do[0] == 1'b0)) begin // if polarity is 1(odd), VC bit is 0(even)
                net_so = 1'b1; // nic send out data
                net_do = out_buffer_do;
            end
            if ((net_polarity == 1'b0) && (out_buffer_do[0] == 1'b1)) begin // if polarity is 0(even), VC bit is 1(odd)
                net_so = 1'b1; // nic send out data
                net_do = out_buffer_do;
            end
        end

        // output buffer logic
        if ((net_so == 1'b1) && (net_ro == 1'b1)) begin // if output buffer has data to read, and is ready to be read 
            out_buffer_re = 1'b1; // output buffer is good to be read
        end
        else begin // if output buffer does not have data to read, or is not ready to be read 
            out_buffer_re = 1'b0; // output buffer is prohibited to be read
            // and no more data will be accepted by output buffer, when it is full(by using qualified enable signal, see buffer design)
        end
    end
    //----------------------------------------------------------------------------------------

    //------------------------------INTERFACING WITH PROCESSOR--------------------------------
    always @(*) begin
        // set initial value
        //out_buffer_we = 1'b0;
        //in_buffer_re = 1'b0;
        d_out = 64'h0; // If not asserted, d_out port assumes 64'h0
    
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
                    2'b00 : begin // addr == 00, processor read out data in input buffer at next clk
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
endmodule
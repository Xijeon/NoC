module cardinal_cpu (clk               //System Clock
					 reset,            // System Reset
					 inst_in,          //Instruction from the Instruction Memory
					 d_in,             // Data from Data Memory
					 pc_out            // Program Counter
					 d_out,            // Write Data to Data Memory
					 addr_out,         // Write Address for Data Memory
					 memWrEn,          // Data Memory Write Enable
					 memEn,            // Data Memory Enable
					 addr_nic,         //Address bits for the NIC interface
					 din_nic,          //Data flowing from Processor to NIC
					 dout_nic,         //Data flowing from NIC to Processor 
					 nicEn,            //Enable signal for NIC
					 nicWrEn);         //Enable Write signal for NIC

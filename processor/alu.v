/*
 * @Name         : 
 * @Version      : 1.0
 * @Author       : Shijie Chen
 * @Email        : shijiec@usc.edu
 * @Date         : 2021-03-25 11:05:36
 * @LastEditors  : Shijie Chen
 * @LastEditTime : 2021-03-25 20:43:12
 * @Description  : 
 */


module alu #(
    parameter    INPUT_WIDTH  = 12,
    parameter    OUTPUT_WIDTH = 12,
)(
    input                           clk_in,
    input                           rst_n,
    input  [INPUT_WIDTH - 1 : 0]    data_in,
    output [OUTPUT_WIDTH - 1 : 0]   data_out
);

endmodule  //alu
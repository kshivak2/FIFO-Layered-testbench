module FIFO (
  input clk, rst, 
  input [7:0] din,
  output reg [7:0] dout,
  output full, empty,
  input rd, wr);
  
  reg [3:0] wptr = 0, rptr = 0;
  reg [4:0] count;
  reg [7:0] mem [15:0];
  
  always@(posedge clk)
    begin
      if(rst) begin
        wptr <= 0;
        rptr <= 0;
        count <= 0;
      end
      
      else if(wr && !full) begin
        mem[wptr] <= din;
        wptr <= wptr+1;
        count <= count+1;
      end
      
      else if (rd && !empty) begin
        dout <= mem[rptr];
        rptr <= rptr+1;
        count <= count-1;
      end
    end
  
  assign full = (count == 16)?1'b1:1'b0;
  assign empty = (count == 0)?1'b1:1'b0;
endmodule


interface fifo;
  logic clk, rst;
  logic [7:0] din;
  logic [7:0] dout;
  logic full, empty;
  logic rd, wr;
endinterface

      
        
class transaction;
  rand bit op;
  bit [7:0] din;
  bit [7:0] dout;
  bit empty;
  bit full;
  bit rd, wr;
  
  constraint open_ctrl {
    op dist {1:/50, 0:/50};
  }
endclass

class generator;
  transaction trans;
  mailbox #(transaction) gen2drv;
  
  event next;
  event done;
  int count;
  
  function new(mailbox #(transaction) gen2drv);
    this.gen2drv = gen2drv;
    trans = new();
  endfunction
  
  task run();
    int i = 0;
  
    repeat(count) begin
      i++;
      assert(trans.randomize()) else $error("RANDOMIZATION FAILED");
      gen2drv.put(trans);
      $display("[GEN] OP : %0d \t ITERATION : %0d", trans.op, i);
      @(next);
    end
  
    ->done;
  endtask
endclass

class driver;
  transaction trans;
  mailbox #(transaction) gen2drv;
  virtual fifo f;
  
  function new(mailbox #(transaction) gen2drv);
    this.gen2drv = gen2drv;
  endfunction
  
  task reset();
    f.rst <= 1;
    f.rd <= 0;
    f.wr <= 0;
    f.din <= 0;
    repeat(5) @(posedge f.clk);
    $display("[DRV] RESET DONE");
    $display("-------------------------------------------------");
    f.rst <= 0;
  endtask
  
  task write();
    @(posedge f.clk);
    f.rst <= 0;
    f.wr <= 1;
    f.rd <= 0;
    f.din <= $urandom_range(1, 10);
    @(posedge f.clk);
    $display("[DRV] DATA WRITTEN : %0d", f.din);
    f.wr <= 0;
  endtask
  
  task read();
    @(posedge f.clk);
    f.rst <= 0;
    f.wr <= 0;
    f.rd <= 1;
    @(posedge f.clk);
    $display("[DRV] DATA READ"); 
    f.rd <= 0;
  endtask
  
  task run();
    forever begin
      gen2drv.get(trans);
      if (trans.op == 1)
        write();
      else
        read();
    end
  endtask
endclass
    
class monitor;
  transaction trans;
  virtual fifo f;
  mailbox #(transaction) mon2sco;
  
  function new(mailbox #(transaction) mon2sco);
    this.mon2sco = mon2sco;
    trans = new();
  endfunction
  
  task run();
    forever begin
      repeat(2) @(posedge f.clk);
      trans.wr = f.wr;
      trans.rd = f.rd;
      trans.din = f.din;
      trans.empty = f.empty;
      trans.full = f.full;
      @(posedge f.clk);
      trans.dout = f.dout;
      mon2sco.put(trans);
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", trans.wr, trans.rd, trans.din, trans.dout, trans.full, trans.empty);
    end
  endtask
endclass

class scoreboard;
  transaction trans;
  mailbox #(transaction) mon2sco;
  
  bit [7:0] din[$];
  int err = 0;
  bit [7:0] temp;
  
  event next;
  
  function new(mailbox #(transaction) mon2sco);
    this.mon2sco = mon2sco;
  endfunction
  
  task run();
    forever begin
      mon2sco.get(trans);
      $display("[SCO] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", trans.wr, trans.rd, trans.din, trans.dout, trans.full, trans.empty);
      
      if (trans.wr == 1'b1) begin
        if (trans.full == 1'b0) begin
          din.push_front(trans.din);
          $display("[SCO] DATA STORED IN QUEUE : %0d", trans.din);
        end else begin
          $display("[SCO] FIFO is FULL");
        end
      end else if (trans.rd == 1'b1) begin
        if (trans.empty == 1'b0) begin
          temp = din.pop_back();
          
          if (trans.dout == temp) begin
            $display("[SCO] DATA MATCH");
          end else begin
            $display("[SCO] DATA MISMATCH: Expected %0d, Got %0d", temp, trans.dout);
            err++;
          end
        end else begin
          $display("[SCO] FIFO IS EMPTY");
        end
      end
      $display("-------------------------------------------------");
      ->next;
    end
  endtask
endclass
      
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  mailbox #(transaction) gen2drv;
  mailbox #(transaction) mon2sco;
  
  event next_env;
  
  virtual fifo f;
  
  function new(virtual fifo f);
    gen2drv = new();
    mon2sco = new();
    gen = new(gen2drv);
    drv = new(gen2drv);
    mon = new(mon2sco);
    sco = new(mon2sco);
    
    this.f = f;
    drv.f = this.f;
    mon.f = this.f;
    
    gen.next = next_env;
    sco.next = next_env;
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered);
    $display("---------------------------------------------");
    $display("Error Count : %0d", sco.err);
    $display("---------------------------------------------");
    $finish;
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass

module tb;
  fifo f();
  FIFO dut(
    .din(f.din), 
    .clk(f.clk), 
    .rst(f.rst), 
    .dout(f.dout), 
    .full(f.full), 
    .empty(f.empty), 
    .rd(f.rd), 
    .wr(f.wr)
  );
  
  initial begin
    f.clk = 0;
  end
  
  always #10 f.clk = ~f.clk;
  
  environment env;
  
  initial begin
    env = new(f);
    env.gen.count = 12;
    env.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
endmodule
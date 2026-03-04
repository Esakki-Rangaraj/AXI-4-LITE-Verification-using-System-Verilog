interface axi_if (input logic ACLK, ARESETN);
    logic        read_s;
    logic        write_s;
    logic [31:0] address;
    logic [31:0] W_data;
    logic [31:0] dbg_rdata;
  	logic s_rvalid;
endinterface


class axi_transaction;
    rand bit        is_write;
    rand bit [31:0] addr;
    rand bit [31:0] wdata;
         bit [31:0] rdata_exp;
         bit [31:0] rdata_act;

    // Instead of word alignment, constrain to 0..31 to match 32 registers
    constraint c_addr_range { addr inside {[0:31]}; }

    function void display(string name);
        $display("---- %s ----", name);
        $display("is_write=%0d addr=0x%08h wdata=0x%08h rdata_exp=0x%08h rdata_act=0x%08h",
                 is_write, addr, wdata, rdata_exp, rdata_act);
    endfunction
endclass


//////////////////////////////////////////////////////////////
// Generator
//////////////////////////////////////////////////////////////
class axi_generator;
    rand axi_transaction t;
    int    no_gen;
    mailbox gen2driv;
    event   ended;

    function new(mailbox gen2driv);
        this.gen2driv = gen2driv;
    endfunction

    task main;
        axi_transaction tr_w, tr_r;
        // no_gen here means number of write-read PAIRS
        repeat (no_gen) begin
            // WRITE transaction
            tr_w = new();
            assert(tr_w.randomize());
            tr_w.is_write = 1;         // force write
            tr_w.display("GEN_WRITE");
            gen2driv.put(tr_w);

            // READ transaction to same address
            tr_r = new();
            tr_r.is_write = 0;         // force read
            tr_r.addr     = tr_w.addr; // same address
            tr_r.wdata    = '0;
            tr_r.display("GEN_READ");
            gen2driv.put(tr_r);
        end
        ->ended;
    endtask
endclass


//////////////////////////////////////////////////////////////
// Driver
//////////////////////////////////////////////////////////////
class axi_driver;
    mailbox       gen2driv;
    int           no_transaction;
    virtual axi_if vif;

    function new(mailbox gen2driv, virtual axi_if vif);
        this.gen2driv = gen2driv;
        this.vif      = vif;
    endfunction

    task reset();
        wait(!vif.ARESETN); // wait reset asserted low
        wait(vif.ARESETN);  // wait deassert
        $display("\tDRIVER RESET COMPLETED");
    endtask

    task main();
        forever begin
            axi_transaction tr;
            gen2driv.get(tr);

            @(posedge vif.ACLK);
            vif.address <= tr.addr;
            vif.W_data  <= tr.wdata;

            if (tr.is_write) begin
                vif.write_s <= 1'b1;
                vif.read_s  <= 1'b0;
            end else begin
                vif.read_s  <= 1'b1;
                vif.write_s <= 1'b0;
            end

            @(posedge vif.ACLK);
            vif.read_s  <= 1'b0;
            vif.write_s <= 1'b0;

            repeat (8) @(posedge vif.ACLK);

            tr.display("DRV");
            no_transaction++;
        end
    endtask
endclass

//////////////////////////////////////////////////////////////
// Monitor
//////////////////////////////////////////////////////////////
class axi_monitor;
    virtual axi_if vif;
    mailbox mon2scb;

    bit [31:0] ref_mem [*];

    function new(mailbox mon2scb, virtual axi_if vif);
        this.mon2scb = mon2scb;
        this.vif     = vif;
    endfunction

    task main();
        forever begin
            axi_transaction tr;
            tr = new();

            @(posedge vif.ACLK);
            wait (vif.read_s || vif.write_s);

            tr.is_write = vif.write_s;
            tr.addr     = vif.address;
            tr.wdata    = vif.W_data;

            if (tr.is_write) begin
                ref_mem[tr.addr] = tr.wdata;
                repeat (8) @(posedge vif.ACLK);
            end else begin
                if (ref_mem.exists(tr.addr))
                    tr.rdata_exp = ref_mem[tr.addr];
                else
                    tr.rdata_exp = '0;
              wait(vif.s_rvalid);
                tr.rdata_act = vif.dbg_rdata;
            end

            tr.display("MON");
            mon2scb.put(tr);
        end
    endtask
endclass

//////////////////////////////////////////////////////////////
// Scoreboard
//////////////////////////////////////////////////////////////
class axi_scb;
    int no_transaction;
    mailbox mon2scb;

    function new(mailbox mon2scb);
        this.mon2scb = mon2scb;
    endfunction

    task main();
        axi_transaction tr;
        forever begin
            mon2scb.get(tr);
            if (!tr.is_write) begin
                if (tr.rdata_exp !== tr.rdata_act) begin
                    $error("[SCB] ERROR addr=0x%08h exp=0x%08h got=0x%08h",
                           tr.addr, tr.rdata_exp, tr.rdata_act);
                end else begin
                    $display("[SCB] PASS  addr=0x%08h data=0x%08h",
                             tr.addr, tr.rdata_act);
                end
            end
            tr.display("SCB");
            no_transaction++;
        end
    endtask
endclass

//////////////////////////////////////////////////////////////
// Environment
//////////////////////////////////////////////////////////////
class axi_env;
    virtual axi_if vif;
    axi_generator gen;
    axi_driver    drv;
    axi_monitor   mon;
    axi_scb       s;

    mailbox gen2driv;
    mailbox mon2scb;

    function new(virtual axi_if vif);
        this.vif = vif;
        gen2driv = new();
        mon2scb  = new();

        gen = new(gen2driv);
        drv = new(gen2driv, vif);
        mon = new(mon2scb, vif);
        s   = new(mon2scb);
    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.main();
            drv.main();
            mon.main();
            s.main();
        join_any
    endtask

    task post_test();
        wait(gen.ended.triggered);
        wait(gen.no_gen == drv.no_transaction);
        wait(gen.no_gen == s.no_transaction);
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass

//////////////////////////////////////////////////////////////
// Program test
//////////////////////////////////////////////////////////////
program axi_test(axi_if intf);
    axi_env e;

    initial begin
        e = new(intf);
        e.gen.no_gen = 10;
        e.run();
    end
endprogram

//////////////////////////////////////////////////////////////
// Top-level testbench
//////////////////////////////////////////////////////////////
module axi_tbench_top;

    bit ACLK;
    bit ARESETN;

    axi_if i_axi(ACLK, ARESETN);
    axi_test t1(i_axi);

    axi4_lite_top dut (
        .ACLK     (ACLK),
        .ARESETN  (ARESETN),
        .read_s   (i_axi.read_s),
        .write_s  (i_axi.write_s),
        .address  (i_axi.address),
        .W_data   (i_axi.W_data),
      .dbg_rdata(i_axi.dbg_rdata),
      .dbg_s_rvalid(i_axi.s_rvalid) 	
    );

    always #5 ACLK = ~ACLK;

    initial begin
        ACLK    = 0;
        ARESETN = 0;
        #20 ARESETN = 1;
    end

    initial begin
        $dumpfile("axi4_lite.vcd");
        $dumpvars(0, axi_tbench_top);
    end

endmodule

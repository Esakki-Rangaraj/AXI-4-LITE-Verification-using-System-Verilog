// Code your design here
module axi4_lite_master #(
    parameter ADDRESS = 32,
    parameter DATA_WIDTH = 32
    )
    (
        //Global Signals
        input                           ACLK,
        input                           ARESETN,

        input                           START_READ,
        input                           START_WRITE,

        input          [ADDRESS-1 : 0]  address,
        input          [DATA_WIDTH-1:0]  W_data,

        //Read Address Channel INPUTS
        input                           M_ARREADY,
        //Read Data Channel INPUTS
        /* verilator lint_off UNUSED */
        input          [DATA_WIDTH-1:0] M_RDATA,
        input               [1:0]       M_RRESP,
        input                           M_RVALID,
        //Write Address Channel INPUTS
        input                           M_AWREADY,
        //
        input                           M_WREADY,
        //Write Response Channel INPUTS
        input             [1:0]         M_BRESP,
        input                           M_BVALID,
        //Read Address Channel OUTPUTS
        output logic    [ADDRESS-1 : 0] M_ARADDR,
        output logic                    M_ARVALID,
        //Read Data Channel OUTPUTS
        output logic                    M_RREADY,
        //Write Address Channel OUTPUTS
        output logic    [ADDRESS-1 : 0] M_AWADDR,
        output logic                    M_AWVALID,
        //Write Data  Channel OUTPUTS
        output logic   [DATA_WIDTH-1:0] M_WDATA,
        output logic   [3:0]            M_WSTRB,
        output logic                    M_WVALID,
        //Write Response Channel OUTPUTS
        output logic                    M_BREADY	
    );
    logic read_start;
    logic write_addr;
    logic write_data;
    logic write_start;

    typedef enum logic [2 : 0] {IDLE,WRITE_CHANNEL,WRESP__CHANNEL, RADDR_CHANNEL, RDATA__CHANNEL} state_type;
    state_type state , next_state;

    //ar
    assign M_ARADDR  = (state == RADDR_CHANNEL) ? address : 32'h0;
    assign M_ARVALID = (state == RADDR_CHANNEL) ? 1 : 0;
    //r
    assign M_RREADY  = (state == RDATA__CHANNEL ||state == RADDR_CHANNEL) ? 1 : 0;
    //aw
    assign M_AWVALID = (state == WRITE_CHANNEL) ? 1 : 0;
    assign M_AWADDR  = (state == WRITE_CHANNEL) ? address : 32'h0;
    assign write_addr = M_AWVALID && M_AWREADY;
    assign write_data = M_WVALID  && M_WREADY;
    //W
    assign M_WVALID  = (state == WRITE_CHANNEL) ? 1 : 0;
    assign M_WDATA   = (state == WRITE_CHANNEL) ? W_data : 32'h0;
    assign M_WSTRB   = (state == WRITE_CHANNEL)  ?4'b1111:0;
    // B
    assign M_BREADY = ((state == WRITE_CHANNEL)||(state == WRESP__CHANNEL)) ? 1 : 0;


    always_ff @(posedge ACLK) begin
        if (~ARESETN) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_ff @(posedge ACLK) begin
        if (~ARESETN) begin
           read_start <= 0;
           write_start<= 0;
        end 
        else begin
           read_start <= START_READ;
           write_start<= START_WRITE;
        end
    end
    
    always_comb begin
		case (state)
            IDLE : begin
                if (write_start) begin
                    next_state = WRITE_CHANNEL;
                end 
                else if (read_start) begin
                    next_state = RADDR_CHANNEL;
                end 
                else begin
                    next_state = IDLE;
                end
            end
			RADDR_CHANNEL  : if (M_ARVALID && M_ARREADY  ) next_state = RDATA__CHANNEL;
			RDATA__CHANNEL : if (M_RVALID  && M_RREADY   ) next_state = IDLE;
            WRITE_CHANNEL  : if (write_addr && write_data) next_state = WRESP__CHANNEL;
            WRESP__CHANNEL : if (M_BVALID  && M_BREADY   ) next_state = IDLE;
			default : next_state = IDLE;
		endcase
	end
endmodule

module axi4_lite_slave #(
    parameter ADDRESS = 32,
    parameter DATA_WIDTH = 32
    )
    (
        //Global Signals
        input                           ACLK,
        input                           ARESETN,

        ////Read Address Channel INPUTS
        input           [ADDRESS-1:0]   S_ARADDR,
        input                           S_ARVALID,
        //Read Data Channel INPUTS
        input                           S_RREADY,
        //Write Address Channel INPUTS
        /* verilator lint_off UNUSED */
        input           [ADDRESS-1:0]   S_AWADDR,
        input                           S_AWVALID,
        //Write Data  Channel INPUTS
        input          [DATA_WIDTH-1:0] S_WDATA,
        input          [3:0]            S_WSTRB,
        input                           S_WVALID,
        //Write Response Channel INPUTS
        input                           S_BREADY,	

        //Read Address Channel OUTPUTS
        output logic                    S_ARREADY,
        //Read Data Channel OUTPUTS
        output logic    [DATA_WIDTH-1:0]S_RDATA,
        output logic         [1:0]      S_RRESP,
        output logic                    S_RVALID,
        //Write Address Channel OUTPUTS
        output logic                    S_AWREADY,
        output logic                    S_WREADY,
        //Write Response Channel OUTPUTS
        output logic         [1:0]      S_BRESP,
        output logic                    S_BVALID
    );

    localparam no_of_registers = 32;

    logic [DATA_WIDTH-1 : 0] register [no_of_registers-1 : 0];
    logic [ADDRESS-1 : 0]    addr;
    logic  write_addr;
    logic  write_data;

    typedef enum logic [2 : 0] {IDLE,WRITE_CHANNEL,WRESP__CHANNEL, RADDR_CHANNEL, RDATA__CHANNEL} state_type;
    state_type state , next_state;

    // AR
    assign S_ARREADY = (state == RADDR_CHANNEL) ? 1 : 0;
    // 
    assign S_RVALID = (state == RDATA__CHANNEL) ? 1 : 0;
    assign S_RDATA  = (state == RDATA__CHANNEL) ? register[addr] : 0;
    assign S_RRESP  = (state == RDATA__CHANNEL) ?2'b00:0;
    // AW
    assign S_AWREADY = (state == WRITE_CHANNEL) ? 1 : 0;
    // W
    assign S_WREADY = (state == WRITE_CHANNEL) ? 1 : 0;
    assign write_addr = S_AWVALID && S_AWREADY;
    assign write_data = S_WREADY &&S_WVALID;
    // B
    assign S_BVALID = (state == WRESP__CHANNEL) ? 1 : 0;
    assign S_BRESP  = (state == WRESP__CHANNEL )? 0:0;

    integer i;

    always_ff @(posedge ACLK) begin
        // Reset the register array
        if (~ARESETN) begin
            for (i = 0; i < 32; i++) begin
                register[i] <= 32'b0;
            end
        end
        else begin
            if (state == WRITE_CHANNEL) begin
                register[S_AWADDR] <= S_WDATA;
            end
            else if (state == RADDR_CHANNEL) begin
                addr <= S_ARADDR;
            end
        end
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always_comb begin
		case (state)
            IDLE : begin
                if (S_AWVALID) begin
                    next_state = WRITE_CHANNEL;
                end 
                else if (S_ARVALID) begin
                    next_state = RADDR_CHANNEL;
                end 
                else begin
                    next_state = IDLE;
                end
            end
            RADDR_CHANNEL   : if (S_ARVALID && S_ARREADY ) next_state = RDATA__CHANNEL;
            RDATA__CHANNEL  : if (S_RVALID  && S_RREADY  ) next_state = IDLE;
            WRITE_CHANNEL   : if (write_addr &&write_data) next_state = WRESP__CHANNEL;
            WRESP__CHANNEL  : if (S_BVALID  && S_BREADY  ) next_state = IDLE;
            default : next_state = IDLE;
        endcase
    end
endmodule

module axi4_lite_top#(
    parameter DATA_WIDTH = 32,
    parameter ADDRESS = 32
    )(
        input                           ACLK,
        input                           ARESETN,
        input                           read_s,
        input                           write_s,
        input    [ADDRESS-1:0]          address,
 		 input    [DATA_WIDTH-1:0]       W_data,
  output   [DATA_WIDTH-1:0]       dbg_rdata,
  		output logic dbg_s_rvalid
    );

    logic  S_ARREADY,S_RVALID,M_ARVALID,M_RREADY,S_AWREADY,S_BVALID,M_AWVALID,M_BREADY,M_WVALID,S_WREADY;
    logic [ADDRESS-1 : 0] M_ARADDR;
    logic [ADDRESS-1 : 0] M_AWADDR;
    logic [DATA_WIDTH-1:0]M_WDATA;
    logic [DATA_WIDTH-1:0]S_RDATA;
    logic [3:0]M_WSTRB;
    logic [1:0]S_RRESP,S_BRESP;
  	assign dbg_rdata = S_RDATA;
	assign dbg_s_rvalid = S_RVALID;
  
    axi4_lite_master u_axi4_lite_master0
    (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .START_READ(read_s),
        .address(address),
        .W_data(W_data),
      .M_ARREADY(S_ARREADY),
        .M_RDATA(S_RDATA),
        .M_RRESP(S_RRESP),
        .M_RVALID(S_RVALID),
        .M_ARADDR(M_ARADDR),
        .M_ARVALID(M_ARVALID),
        .M_RREADY(M_RREADY),
        .START_WRITE(write_s),
        .M_AWREADY(S_AWREADY),
        .M_WVALID(M_WVALID),
        .M_WREADY(S_WREADY),
        .M_BRESP(S_BRESP),
        .M_BVALID(S_BVALID),
        .M_AWADDR(M_AWADDR),
        .M_AWVALID(M_AWVALID),
        .M_WDATA(M_WDATA),
        .M_WSTRB(M_WSTRB),
        .M_BREADY(M_BREADY)
    );

    axi4_lite_slave u_axi4_lite_slave0
    (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
      .S_ARREADY(S_ARREADY),
        .S_RDATA(S_RDATA),
        .S_RRESP(S_RRESP),
        .S_RVALID(S_RVALID),
        .S_ARADDR(M_ARADDR),
        .S_ARVALID(M_ARVALID),
        .S_RREADY(M_RREADY),
        .S_AWREADY(S_AWREADY),
        .S_WVALID(M_WVALID),
        .S_WREADY(S_WREADY),
        .S_BRESP(S_BRESP),
        .S_BVALID(S_BVALID),
        .S_AWADDR(M_AWADDR),
        .S_AWVALID(M_AWVALID),
        .S_WDATA(M_WDATA),
        .S_WSTRB(M_WSTRB),
        .S_BREADY(M_BREADY)
    );
endmodule

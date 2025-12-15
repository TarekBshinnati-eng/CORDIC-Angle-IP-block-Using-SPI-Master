`timescale 1 ns / 1 ps

module spi_master_slave_lite_v1_0_S00_AXI #(
   parameter integer C_S_AXI_DATA_WIDTH = 32,
   parameter integer C_S_AXI_ADDR_WIDTH = 6
) (
   // User ports
   output wire       SPI_SCLK,
   input wire        SPI_MISO,
   output wire       SPI_MOSI,
   output wire       SPI_CS,

   // AXI4-Lite ports
   input wire                                  S_AXI_ACLK,
   input wire                                  S_AXI_ARESETN,
   input wire [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_AWADDR,
   input wire [2:0]                            S_AXI_AWPROT,
   input wire                                  S_AXI_AWVALID,
   output wire                                 S_AXI_AWREADY,
   input wire [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_WDATA,
   input wire [(C_S_AXI_DATA_WIDTH/8)-1:0]     S_AXI_WSTRB,
   input wire                                  S_AXI_WVALID,
   output wire                                 S_AXI_WREADY,
   output wire [1:0]                           S_AXI_BRESP,
   output wire                                 S_AXI_BVALID,
   input wire                                  S_AXI_BREADY,
   input wire [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_ARADDR,
   input wire [2:0]                            S_AXI_ARPROT,
   input wire                                  S_AXI_ARVALID,
   output wire                                 S_AXI_ARREADY,
   output wire [C_S_AXI_DATA_WIDTH-1:0]        S_AXI_RDATA,
   output wire [1:0]                           S_AXI_RRESP,
   output wire                                 S_AXI_RVALID,
   input wire                                  S_AXI_RREADY
);

   // AXI4LITE signals
   reg [C_S_AXI_ADDR_WIDTH-1:0]   axi_awaddr;
   reg                            axi_awready;
   reg                            axi_wready;
   reg [1:0]                      axi_bresp;
   reg                            axi_bvalid;
   reg [C_S_AXI_ADDR_WIDTH-1:0]   axi_araddr;
   reg                            axi_arready;
   reg [C_S_AXI_DATA_WIDTH-1:0]   axi_rdata;
   reg [1:0]                      axi_rresp;
   reg                            axi_rvalid;

   // Local parameters
   localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
   localparam integer OPT_MEM_ADDR_BITS = 3;
   
   // Slave registers
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg0;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg1;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg2;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg3;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg4;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg5;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg6;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg7;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg8;
   reg [C_S_AXI_DATA_WIDTH-1:0]   slv_reg9;
   
   wire                           slv_reg_rden;
   wire                           slv_reg_wren;
   reg [C_S_AXI_DATA_WIDTH-1:0]   reg_data_out;
   integer                        byte_index;

   // SPI Master signals
   wire [1:0]  w_spi_mode;
   wire [15:0] w_clk_scale;
   wire [7:0]  w_cs_inactive_clks;
   
   wire [5:0]  w_tx_count;
   reg  [7:0]  w_tx_byte;
   reg         w_tx_dv;
   wire        w_tx_ready;
   
   wire [5:0]  w_rx_count;
   wire        w_rx_dv;
   wire [7:0]  w_rx_byte;

   // TX state machine
   localparam TX_IDLE  = 2'b00;
   localparam TX_START = 2'b01;
   localparam TX_BUSY  = 2'b10;
   
   reg [1:0]   tx_state;
   reg [4:0]   tx_counter;
   reg [4:0]   max_tx_counter;
   reg [4:0]   tx_byte_index;
   wire        tx_en;

   wire        w_spi_cs_n;

   reg [C_S_AXI_DATA_WIDTH-1:0]   r_rx_data0;
   reg [C_S_AXI_DATA_WIDTH-1:0]   r_rx_data1;
   reg [C_S_AXI_DATA_WIDTH-1:0]   r_rx_data2;
   reg [C_S_AXI_DATA_WIDTH-1:0]   r_rx_data3;

   // I/O Connections assignments
   assign S_AXI_AWREADY = axi_awready;
   assign S_AXI_WREADY  = axi_wready;
   assign S_AXI_BRESP   = axi_bresp;
   assign S_AXI_BVALID  = axi_bvalid;
   assign S_AXI_ARREADY = axi_arready;
   assign S_AXI_RDATA   = axi_rdata;
   assign S_AXI_RRESP   = axi_rresp;
   assign S_AXI_RVALID  = axi_rvalid;

   // Implement axi_awready generation
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_awready <= 1'b0;
      end else begin
         if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
            axi_awready <= 1'b1;
         end else begin
            axi_awready <= 1'b0;
         end
      end
   end

   // Implement axi_awaddr latching
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
      end else begin
         if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
            axi_awaddr <= S_AXI_AWADDR;
         end
      end
   end

   // Implement axi_wready generation
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_wready <= 1'b0;
      end else begin
         if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID) begin
            axi_wready <= 1'b1;
         end else begin
            axi_wready <= 1'b0;
         end
      end
   end

   // Implement memory mapped register select and write logic
   assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         slv_reg0 <= 32'h00500063;
         slv_reg1 <= 32'h00000002;
         slv_reg2 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         slv_reg3 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         slv_reg4 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         slv_reg5 <= {C_S_AXI_DATA_WIDTH{1'b0}};
      end else begin
         if (slv_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
               4'b0000: begin
                  for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1)
                     if (S_AXI_WSTRB[byte_index])
                        slv_reg0[byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
               end
               4'b0001: begin
                  for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1)
                     if (S_AXI_WSTRB[byte_index])
                        slv_reg1[byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
               end
               4'b0010: begin
                  for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1)
                     if (S_AXI_WSTRB[byte_index])
                        slv_reg2[byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
               end
               4'b0011: begin
                  for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1)
                     if (S_AXI_WSTRB[byte_index])
                        slv_reg3[byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
               end
               4'b0100: begin
                  for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1)
                     if (S_AXI_WSTRB[byte_index])
                        slv_reg4[byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
               end
               4'b0101: begin
                  for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1)
                     if (S_AXI_WSTRB[byte_index])
                        slv_reg5[byte_index*8 +: 8] <= S_AXI_WDATA[byte_index*8 +: 8];
               end
               default: begin
                  slv_reg0 <= slv_reg0;
                  slv_reg1 <= slv_reg1;
                  slv_reg2 <= slv_reg2;
                  slv_reg3 <= slv_reg3;
                  slv_reg4 <= slv_reg4;
                  slv_reg5 <= slv_reg5;
               end
            endcase
         end
      end
   end

   // Implement write response logic
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_bvalid <= 1'b0;
         axi_bresp  <= 2'b00;
      end else begin
         if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && !axi_bvalid) begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b00;
         end else if (S_AXI_BREADY && axi_bvalid) begin
            axi_bvalid <= 1'b0;
         end
      end
   end

   // Implement axi_arready generation
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_arready <= 1'b0;
         axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b1}};
      end else begin
         if (!axi_arready && S_AXI_ARVALID) begin
            axi_arready <= 1'b1;
            axi_araddr  <= S_AXI_ARADDR;
         end else begin
            axi_arready <= 1'b0;
         end
      end
   end

   // Implement axi_rvalid generation
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_rvalid <= 1'b0;
         axi_rresp  <= 2'b00;
      end else begin
         if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b00;
         end else if (axi_rvalid && S_AXI_RREADY) begin
            axi_rvalid <= 1'b0;
         end
      end
   end

   // Implement memory mapped register select and read logic
   assign slv_reg_rden = axi_arready && S_AXI_ARVALID && !axi_rvalid;

   always @(*) begin
      case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
         4'b0000: reg_data_out = slv_reg0;
         4'b0001: reg_data_out = slv_reg1;
         4'b0010: reg_data_out = slv_reg2;
         4'b0011: reg_data_out = slv_reg3;
         4'b0100: reg_data_out = slv_reg4;
         4'b0101: reg_data_out = slv_reg5;
         4'b0110: reg_data_out = slv_reg6;
         4'b0111: reg_data_out = slv_reg7;
         4'b1000: reg_data_out = slv_reg8;
         4'b1001: reg_data_out = slv_reg9;
         default: reg_data_out = {C_S_AXI_DATA_WIDTH{1'b0}};
      endcase
   end

   // Output register or memory read data
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
      end else begin
         if (slv_reg_rden) begin
            axi_rdata <= reg_data_out;
         end
      end
   end

   // User logic - SPI Master instantiation
   spi_master_cs spi_master_cs_inst (
      .i_Rst_L(S_AXI_ARESETN),
      .i_Clk(S_AXI_ACLK),
      .i_spi_mode(w_spi_mode),
      .i_clk_scale(w_clk_scale),
      .i_cs_inactive_clks(w_cs_inactive_clks),
      
      .i_TX_Count(w_tx_count),
      .i_TX_Byte(w_tx_byte),
      .i_TX_DV(w_tx_dv),
      .o_TX_Ready(w_tx_ready),
      
      .o_RX_Count(w_rx_count),
      .o_RX_DV(w_rx_dv),
      .o_RX_Byte(w_rx_byte),
      
      .o_SPI_Clk(SPI_SCLK),
      .i_SPI_MISO(SPI_MISO),
      .o_SPI_MOSI(SPI_MOSI),
      .o_SPI_CS_n(w_spi_cs_n)
   );

   assign SPI_CS = w_spi_cs_n;
   
   assign w_spi_mode = slv_reg0[1:0];
   assign w_clk_scale = slv_reg0[17:2];
   assign w_cs_inactive_clks = slv_reg0[25:18];
   
   assign w_tx_count = slv_reg1[5:0];

   // TX state machine
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         tx_state <= TX_IDLE;
      end else begin
         case (tx_state)
            TX_IDLE: begin
               if (tx_counter > 0 && w_tx_ready) begin
                  tx_state <= TX_START;
               end else begin
                  tx_state <= TX_IDLE;
               end
            end
            
            TX_START: begin
               tx_state <= TX_BUSY;
            end
            
            TX_BUSY: begin
               if (w_tx_ready) begin
                  tx_state <= TX_IDLE;
               end else begin
                  tx_state <= TX_BUSY;
               end
            end
            
            default: begin
               tx_state <= tx_state;
            end
         endcase
      end
   end

   always @(*) begin
      w_tx_dv = (tx_state == TX_START) ? 1'b1 : 1'b0;
   end

   assign tx_en = (axi_awaddr == 6'b000100 && S_AXI_WVALID) ? 1'b1 : 1'b0;

   always @(posedge S_AXI_ACLK) begin
      if (tx_en) begin
         tx_counter <= S_AXI_WDATA[5:0];
         max_tx_counter <= S_AXI_WDATA[5:0];
      end else if (tx_counter > 0 && w_tx_dv) begin
         tx_counter <= tx_counter - 5'd1;
      end
   end

   

   always @(*) begin
	tx_byte_index = max_tx_counter - tx_counter;  // calc index
      case (tx_byte_index)
         5'd0:    w_tx_byte = slv_reg2[7:0];
         5'd1:    w_tx_byte = slv_reg2[15:8];
         5'd2:    w_tx_byte = slv_reg2[23:16];
         5'd3:    w_tx_byte = slv_reg2[31:24];
         
         5'd4:    w_tx_byte = slv_reg3[7:0];
         5'd5:    w_tx_byte = slv_reg3[15:8];
         5'd6:    w_tx_byte = slv_reg3[23:16];
         5'd7:    w_tx_byte = slv_reg3[31:24];
         
         5'd8:    w_tx_byte = slv_reg4[7:0];
         5'd9:    w_tx_byte = slv_reg4[15:8];
         5'd10:   w_tx_byte = slv_reg4[23:16];
         5'd11:   w_tx_byte = slv_reg4[31:24];
         
         5'd12:   w_tx_byte = slv_reg5[7:0];
         5'd13:   w_tx_byte = slv_reg5[15:8];
         5'd14:   w_tx_byte = slv_reg5[23:16];
         5'd15:   w_tx_byte = slv_reg5[31:24];
         
         default: w_tx_byte = 8'h00;
      endcase
   end

   // RX data capture
   always @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
         r_rx_data0 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         r_rx_data1 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         r_rx_data2 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         r_rx_data3 <= {C_S_AXI_DATA_WIDTH{1'b0}};
      end else if (w_rx_dv) begin
         case (w_rx_count)
            6'b000000: r_rx_data0[7:0]   <= w_rx_byte;
            6'b000001: r_rx_data0[15:8]  <= w_rx_byte;
            6'b000010: r_rx_data0[23:16] <= w_rx_byte;
            6'b000011: r_rx_data0[31:24] <= w_rx_byte;
            
            6'b000100: r_rx_data1[7:0]   <= w_rx_byte;
            6'b000101: r_rx_data1[15:8]  <= w_rx_byte;
            6'b000110: r_rx_data1[23:16] <= w_rx_byte;
            6'b000111: r_rx_data1[31:24] <= w_rx_byte;
            
            6'b001000: r_rx_data2[7:0]   <= w_rx_byte;
            6'b001001: r_rx_data2[15:8]  <= w_rx_byte;
            6'b001010: r_rx_data2[23:16] <= w_rx_byte;
            6'b001011: r_rx_data2[31:24] <= w_rx_byte;
            
            6'b001100: r_rx_data3[7:0]   <= w_rx_byte;
            6'b001101: r_rx_data3[15:8]  <= w_rx_byte;
            6'b001110: r_rx_data3[23:16] <= w_rx_byte;
            6'b001111: r_rx_data3[31:24] <= w_rx_byte;
            
            default: begin
               r_rx_data0 <= r_rx_data0;
               r_rx_data1 <= r_rx_data1;
               r_rx_data2 <= r_rx_data2;
               r_rx_data3 <= r_rx_data3;
            end
         endcase
      end
   end

   // Copy RX data to read registers when CS goes high
   always @(posedge S_AXI_ACLK) begin
      slv_reg6 <= slv_reg6;
      slv_reg7 <= slv_reg7;
      slv_reg8 <= slv_reg8;
      slv_reg9 <= slv_reg9;

      if (!S_AXI_ARESETN) begin
         slv_reg6 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         slv_reg7 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         slv_reg8 <= {C_S_AXI_DATA_WIDTH{1'b0}};
         slv_reg9 <= {C_S_AXI_DATA_WIDTH{1'b0}};
      end else if (w_spi_cs_n) begin
         slv_reg6 <= r_rx_data0;
         slv_reg7 <= r_rx_data1;
         slv_reg8 <= r_rx_data2;
         slv_reg9 <= r_rx_data3;
      end
   end

endmodule

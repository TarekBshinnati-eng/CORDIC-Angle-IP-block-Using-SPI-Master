///////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              With single chip-select (AKA Slave Select) capability
//
//              Supports arbitrary length byte transfers.
// 
//              Instantiates a SPI Master and adds single CS.
//              If multiple CS signals are needed, will need to use different
//              module, OR multiplex the CS from this at a higher level.
//
// Note:        i_Clk must be at least 2x faster than i_SPI_Clk
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
//              MAX_BYTES_PER_CS - Set to the maximum number of bytes that
//              will be sent during a single CS-low pulse.
// 
//              CS_INACTIVE_CLKS - Sets the amount of time in clock cycles to
//              hold the state of Chip-Selct high (inactive) before next 
//              command is allowed on the line.  Useful if chip requires some
//              time when CS is high between trasnfers.
///////////////////////////////////////////////////////////////////////////////

module spi_master_cs (
   // Control/Data Signals
   input wire        i_Rst_L,              // FPGA Reset
   input wire        i_Clk,                // FPGA Clock
   input wire [1:0]  i_spi_mode,           // SPI_MODE
   input wire [15:0] i_clk_scale,          // clk scale factor
   input wire [7:0]  i_cs_inactive_clks,   // CS inactive clocks
   
   // TX (MOSI) Signals
   input wire [5:0]  i_TX_Count,           // # bytes per CS low (max. 16)
   input wire [7:0]  i_TX_Byte,            // Byte to transmit on MOSI
   input wire        i_TX_DV,              // Data Valid Pulse with i_TX_Byte
   output wire       o_TX_Ready,           // Transmit Ready for next byte
   
   // RX (MISO) Signals
   output wire [5:0] o_RX_Count,           // Index RX byte
   output wire       o_RX_DV,              // Data Valid pulse (1 clock cycle)
   output wire [7:0] o_RX_Byte,            // Byte received on MISO

   // SPI Interface
   output wire       o_SPI_Clk,
   input wire        i_SPI_MISO,
   output wire       o_SPI_MOSI,
   output wire       o_SPI_CS_n
);

   // State machine states
   localparam IDLE        = 2'b00;
   localparam TRANSFER    = 2'b01;
   localparam CS_INACTIVE = 2'b10;

   reg [1:0]  r_SM_CS;
   reg        r_CS_n;
   reg [7:0]  r_CS_Inactive_Count;
   reg [3:0]  r_TX_Count;
   wire       w_Master_Ready;

   wire [7:0] CS_INACTIVE_CLKS;
  
   reg [5:0]  RX_Count;
   wire       RX_DV;

   assign CS_INACTIVE_CLKS = i_cs_inactive_clks;
  
   assign o_RX_Count = RX_Count;
   assign o_RX_DV = RX_DV;

   // Instantiate Master
   spi_master_core spi_master_core_inst (
      // Control/Data Signals
      .i_Rst_L(i_Rst_L),              // FPGA Reset
      .i_Clk(i_Clk),                  // FPGA Clock
      .i_spi_mode(i_spi_mode),        // SPI mode
      .i_clk_scale(i_clk_scale),      // clk scale factor

      // TX (MOSI) Signals
      .i_TX_Byte(i_TX_Byte),          // Byte to transmit
      .i_TX_DV(i_TX_DV),              // Data Valid pulse
      .o_TX_Ready(w_Master_Ready),    // Transmit Ready for Byte
      
      // RX (MISO) Signals
      .o_RX_DV(RX_DV),                // Data Valid pulse
      .o_RX_Byte(o_RX_Byte),          // Byte received on MISO
      
      // SPI Interface
      .o_SPI_Clk(o_SPI_Clk),
      .i_SPI_MISO(i_SPI_MISO),
      .o_SPI_MOSI(o_SPI_MOSI)
   );

   // Purpose: Control CS line using State Machine
   always @(posedge i_Clk or negedge i_Rst_L) begin
      if (!i_Rst_L) begin
         r_SM_CS             <= IDLE;
         r_CS_n              <= 1'b1;   // Resets to high
         r_TX_Count          <= 4'd0;
         r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
      end else begin
         case (r_SM_CS)
            IDLE: begin
               if (r_CS_n == 1'b1 && i_TX_DV == 1'b1) begin // Start of transmission
                  r_TX_Count <= i_TX_Count - 6'd1;  // Register TX Count
                  r_CS_n     <= 1'b0;               // Drive CS low
                  r_SM_CS    <= TRANSFER;           // Transfer bytes
               end
            end

            TRANSFER: begin
               // Wait until SPI is done transferring do next thing
               if (w_Master_Ready == 1'b1) begin
                  if (r_TX_Count > 0) begin
                     if (i_TX_DV == 1'b1) begin
                        r_TX_Count <= r_TX_Count - 4'd1;
                     end
                  end else begin
                     r_CS_n              <= 1'b1;  // we done, so set CS high
                     r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
                     r_SM_CS             <= CS_INACTIVE;
                  end
               end
            end
          
            CS_INACTIVE: begin
               if (r_CS_Inactive_Count > 0) begin
                  r_CS_Inactive_Count <= r_CS_Inactive_Count - 8'd1;
               end else begin
                  r_SM_CS <= IDLE;
               end
            end

            default: begin
               r_CS_n  <= 1'b1;  // we done, so set CS high
               r_SM_CS <= IDLE;
            end
         endcase
      end
   end

   // Purpose: Keep track of RX_Count
   always @(posedge i_Clk) begin
      if (r_CS_n == 1'b1) begin
         RX_Count <= 6'b000000;
      end else if (RX_DV == 1'b1) begin
         RX_Count <= RX_Count + 6'd1;
      end
   end

   assign o_SPI_CS_n = r_CS_n;

   assign o_TX_Ready = (i_TX_DV != 1'b1 && ((r_SM_CS == IDLE) || 
                       (r_SM_CS == TRANSFER && w_Master_Ready == 1'b1 && r_TX_Count > 0))) ? 1'b1 : 1'b0;

endmodule

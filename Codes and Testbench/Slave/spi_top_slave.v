// ============================================================
// File: slave_top.v
// Top-level for the SLAVE board.
// Instantiates a single SPI slave and connects it to
// the clock, a reset button, and the expansion connector.
// ============================================================
`default_nettype none
module slave_top (
    input  wire clk,   // 100 MHz clock from oscillator
    input  wire rst_btn, // A reset button (e.g., btn[0])

    // --- SPI ports from Expansion Connector ---
    input  wire spi_sclk_in,
    input  wire spi_mosi_in,
    input  wire spi_cs_n_in,
    output wire spi_miso_out,
    output wire [15:0] led
);
    wire       write_pulse_wire;
wire [15:0] data_to_led_wire;

reg [15:0] latched_led_data;

always @(posedge clk or posedge rst_btn) begin
    if (rst_btn) begin
        latched_led_data <= 16'h0000;
    end else if (write_pulse_wire) begin
        // On the 1-cycle write pulse, latch the data
        latched_led_data <= data_to_led_wire;
    end
end

assign led = latched_led_data;
    // Instantiate one slave.
    // The MY_ID parameter is not actually used in your
    // slave FSM, but we set it to 0 for clarity.
    spi_slave_fsm #(.MY_ID(3'd0)) u_spi_slave_0 (
        .clk   (clk),
        .rst   (rst_btn),
        
        .sclk  (spi_sclk_in),  // Was sclk [cite: 183]
        .mosi  (spi_mosi_in),  // Was mosi [cite: 183]
        .miso  (spi_miso_out), // Was slave_miso_bus[i] [cite: 183]
        .cs_n  (spi_cs_n_in) ,  // Was cs_n[i] [cite: 183]
        
        // --- ADD these connections ---
    .led_we_pulse  (write_pulse_wire),
    .led_data_out  (data_to_led_wire)
    );

endmodule
`default_nettype wire
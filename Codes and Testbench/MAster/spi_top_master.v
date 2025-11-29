// ============================================================
// File: master_top.v (MODIFIED to add VIO core)
// ============================================================
`default_nettype none
module master_top (
    input  wire        clk,
    input  wire [15:0] sw,
    input  wire [3:0]  btn,
    output wire [15:0] led,
    output wire [2:0]  RGB0,
    output wire [2:0]  RGB1,

    output wire        spi_sclk_out,
    output wire        spi_mosi_out,
    output wire [7:0]  spi_cs_n_out,
    input  wire        spi_miso_in
);

    wire sys_reset = btn[0];

    // ... (internal control/master wires are unchanged) ...
    (* mark_debug="true" *) wire        master_start_tx;
    (* mark_debug="true" *) wire        master_spi_busy;
    (* mark_debug="true" *) wire        master_tx_done;
    (* mark_debug="true" *) wire [15:0] master_cmd_packet;
    (* mark_debug="true" *) wire [15:0] master_data_wr;
    (* mark_debug="true" *) wire [15:0] master_data_rd;
    wire led_red_wire, led_blue_wire, led_green_wire, led_green_write_wire;


    // --- NEW: VIO Wires ---
    wire        vio_mode_wire;
    wire [31:0] vio_cmd_data_wire;
    wire        vio_latch_wire;
    wire        vio_write_wire;
    wire        vio_read_wire;
    // ----------------------

    // Control FSM (MODIFIED Instantiation)
    system_control_fsm u_control_fsm (
        .clk               (clk),
        .rst               (sys_reset),
        .sw_in             (sw),
        .btn_latch         (btn[2]),
        .btn_write_single  (btn[3]),
        .btn_read_single   (btn[1]),

        // --- NEW: VIO Ports ---
        .vio_mode          (vio_mode_wire),
        .vio_cmd_data_in   (vio_cmd_data_wire),
        .vio_latch_trig    (vio_latch_wire),
        .vio_write_trig    (vio_write_wire),
        .vio_read_trig     (vio_read_wire),
        // ----------------------

        .led_data_out      (led),
        .led_red_out       (led_red_wire),
        .led_blue_out      (led_blue_wire),
        .led_green_out     (led_green_wire),
        .led_write_done_g  (led_green_write_wire),
        .latched_id_out    (),
        .master_start_tx   (master_start_tx),
        .master_spi_busy   (master_spi_busy),
        .master_tx_done    (master_tx_done),
        .master_cmd_packet (master_cmd_packet),
        .master_data_wr    (master_data_wr),
        .master_data_rd    (master_data_rd)
    );

    // --- NEW: VIO Core Instantiation ---
    // You must add a VIO IP Core named 'vio_0' to your project
    // with the settings described below.
    vio_0 u_vio_0 (
        .clk            (clk),
        .probe_out0     (vio_mode_wire),       // 1-bit
        .probe_out1     (vio_cmd_data_wire),   // 32-bit
        .probe_out2     (vio_latch_wire),      // 1-bit
        .probe_out3     (vio_write_wire),      // 1-bit
        .probe_out4     (vio_read_wire)        // 1-bit
    );
    // -----------------------------------

    // ... (SPI Master and RGB logic is unchanged) ...
    spi_master_fsm #(.SCLK_DIV(8)) u_spi_master (
        .clk           (clk),
        .rst           (sys_reset),
        .start_tx      (master_start_tx),
        .cmd_packet_in (master_cmd_packet),
        .data_out_in   (master_data_wr),
        .spi_busy      (master_spi_busy),
        .tx_done       (master_tx_done),
        .data_read_out (master_data_rd),
        .sclk_out      (spi_sclk_out),
        .mosi_out      (spi_mosi_out),
        .miso_in       (spi_miso_in),
        .cs_n_out      (spi_cs_n_out)
    );

    assign RGB0[0] = led_red_wire;
    assign RGB0[1] = led_green_wire;
    assign RGB0[2] = led_blue_wire;
    assign RGB1[0] = 1'b0;
    assign RGB1[1] = led_green_write_wire;
    assign RGB1[2] = 1'b0;
endmodule
`default_nettype wire
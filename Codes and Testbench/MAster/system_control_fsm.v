// ============================================================
// system_control_fsm.v
// (MODIFIED to accept VIO override - Syntax Corrected)
// ============================================================
`default_nettype none
module system_control_fsm (
    input  wire        clk,
    input  wire        rst,

    // Switches
    input  wire [15:0] sw_in,

    // Buttons
    input  wire        btn_latch,
    input  wire        btn_write_single,
    input  wire        btn_read_single,

    // --- NEW: VIO Inputs ---
    input  wire        vio_mode,          // 1=VIO, 0=Switches
    input  wire [31:0] vio_cmd_data_in,   // [31:16]=Latch, [15:0]=Write
    input  wire        vio_latch_trig,
    input  wire        vio_write_trig,
    input  wire        vio_read_trig,
    // -----------------------

    // LEDs
    output reg  [15:0] led_data_out,
    output reg         led_red_out,
    output reg         led_blue_out,
    output reg         led_green_out,
    output reg         led_write_done_g,

    // For MISO mux (disconnected in master_top)
    output reg  [2:0]  latched_id_out,

    // SPI master interface
    output reg         master_start_tx,
    input  wire        master_spi_busy,
    input  wire        master_tx_done,
    output reg  [15:0] master_cmd_packet,
    output reg  [15:0] master_data_wr,
    input  wire [15:0] master_data_rd
);

    // --------- Latched command fields ----------
    reg [2:0] latched_id;
    reg [7:0] latched_addr;
    reg       latched_global;

    // --------- Write mode helpers ----------
    reg       last_op_was_write;
    reg       global_mode;
    reg [2:0] gw_idx;
    reg [15:0] latched_write_data;

    // --------- States ----------
    localparam [3:0]
        S_IDLE         = 4'd0,
        S_LATCH_CMD    = 4'd1,
        S_AWAIT_CMD    = 4'd2,
        S_START_TX     = 4'd3,
        S_WAIT_MASTER  = 4'd4,
        S_DISPLAY_READ = 4'd5,
        S_START_TIMER  = 4'd6,
        S_WAIT_TIMER   = 4'd7,
        S_GW_BUILD     = 4'd8,
        S_GW_START     = 4'd9,
        S_GW_WAIT      = 4'd10,
        S_GW_NEXT      = 4'd11,
        S_GW_DONE      = 4'd12;

    reg [3:0] state;

    // --------- Debounce (Physical buttons only) ----------
    wire btn_latch_db, btn_write_s_db, btn_read_s_db;
    debounce u_db_latch   (.clk(clk), .rst(rst), .noisy_in(btn_latch),        .debounced_out(btn_latch_db));
    debounce u_db_write_s (.clk(clk), .rst(rst), .noisy_in(btn_write_single), .debounced_out(btn_write_s_db));
    debounce u_db_read_s  (.clk(clk), .rst(rst), .noisy_in(btn_read_single),  .debounced_out(btn_read_s_db));

    // --------- 3s timer ----------
    reg  timer_start;
    wire timer_done;
    timer_3sec u_timer (.clk(clk), .rst(rst), .start(timer_start), .done(timer_done));

    // --- NEW: Input Mux Logic ---
    wire latch_event = (vio_mode ? vio_latch_trig : btn_latch_db);
    wire write_event = (vio_mode ? vio_write_trig : btn_write_s_db);
    wire read_event  = (vio_mode ? vio_read_trig  : btn_read_s_db);

    // VIO[31:16] = Latch command (ID, ADDR, GLOBAL)
    // VIO[15:0]  = Write data
    wire [15:0] latch_source = vio_mode ? vio_cmd_data_in[31:16] : sw_in;
    wire [15:0] write_source = vio_mode ? vio_cmd_data_in[15:0]  : sw_in;
    // ----------------------------

    // --------- Main FSM ----------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= S_IDLE;
            latched_id        <= 3'd0;
            latched_addr      <= 8'd0;
            latched_global    <= 1'b0;
            latched_id_out    <= 3'd0;

            master_start_tx   <= 1'b0;
            master_cmd_packet <= 16'h0000;
            master_data_wr    <= 16'h0000;

            led_data_out      <= 16'h0000;
            led_red_out       <= 1'b0;
            led_green_out     <= 1'b0;
            led_blue_out      <= 1'b0;
            led_write_done_g  <= 1'b0;

            timer_start       <= 1'b0;
            last_op_was_write <= 1'b0;
            global_mode       <= 1'b0;
            gw_idx            <= 3'd0;
            latched_write_data<= 16'h0000;
        end else begin
            // defaults
            master_start_tx  <= 1'b0;
            timer_start      <= 1'b0;
            led_write_done_g <= 1'b0;

            case (state)
            // --------------------------------------------------
            S_IDLE: begin
                led_red_out  <= 1'b0;
                
                if (latch_event) begin
                    state <= S_LATCH_CMD;
                end else if (write_event) begin
                    // Capture DATA now
                    latched_write_data <= write_source;
                    last_op_was_write  <= 1'b1;

                    if (latched_global) begin
                        // GLOBAL write
                        global_mode  <= 1'b1;
                        gw_idx       <= 3'd0;
                        led_blue_out <= 1'b1;
                        state        <= S_GW_BUILD;
                    end else begin
                        // Single write
                        global_mode        <= 1'b0;
                        master_cmd_packet  <= {2'b00, latched_id, latched_addr, 1'b0/*GLOBAL*/, 1'b0/*WRITE*/, 1'b0};
                        master_data_wr     <= write_source;
                        led_blue_out       <= 1'b1;
                        state              <= S_START_TX;
                    end

                end else if (read_event) begin
                    // READ
                    last_op_was_write  <= 1'b0;
                    global_mode        <= 1'b0;
                    master_cmd_packet  <= {2'b00, latched_id, latched_addr, 1'b0/*GLOBAL*/, 1'b1/*READ*/, 1'b0};
                    master_data_wr     <= 16'h0000;
                    state              <= S_START_TX;
                end
            end

            // --------------------------------------------------
            S_LATCH_CMD: begin
                // Capture ID, ADDR, and GLOBAL flag from selected source
                latched_id        <= latch_source[10:8];
                latched_addr      <= latch_source[7:0];
                latched_global    <= latch_source[15];
                latched_id_out    <= latch_source[10:8];
                
                led_red_out       <= 1'b1;
                state             <= S_AWAIT_CMD;
            end

            // --------------------------------------------------
            S_AWAIT_CMD: begin
                led_red_out <= 1'b0;
                if (latch_event) begin
                    state <= S_LATCH_CMD;
                end else if (write_event) begin
                    // Capture DATA now
                    latched_write_data <= write_source;
                    last_op_was_write  <= 1'b1;

                    if (latched_global) begin
                        global_mode  <= 1'b1;
                        gw_idx       <= 3'd0;
                        led_blue_out <= 1'b1;
                        state        <= S_GW_BUILD;
                    end else begin
                        global_mode        <= 1'b0;
                        master_cmd_packet  <= {2'b00, latched_id, latched_addr, 1'b0/*GLOBAL*/, 1'b0/*WRITE*/, 1'b0};
                        master_data_wr     <= write_source;
                        led_blue_out       <= 1'b1;
                        state              <= S_START_TX;
                    end

                end else if (read_event) begin
                    last_op_was_write  <= 1'b0;
                    global_mode        <= 1'b0;
                    master_cmd_packet  <= {2'b00, latched_id, latched_addr, 1'b0/*GLOBAL*/, 1'b1/*READ*/, 1'b0};
                    master_data_wr     <= 16'h0000;
                    state              <= S_START_TX;
                end
            end

            // --------------------------------------------------
            // Single transfer start/wait
            S_START_TX: begin
                if (!master_spi_busy) begin
                    master_start_tx <= 1'b1;
                    state           <= S_WAIT_MASTER;
                end
            end

            S_WAIT_MASTER: begin
                if (master_tx_done) begin
                    if (last_op_was_write) begin
                        // Single write completed
                        led_write_done_g <= 1'b1;
                        timer_start      <= 1'b1;
                        state            <= S_START_TIMER;
                    end else begin
                        state <= S_DISPLAY_READ;
                    end
                end
            end

            // --------------------------------------------------
            // GLOBAL WRITE loop over IDs 0..7
            S_GW_BUILD: begin
                master_cmd_packet <= {2'b00, gw_idx[2:0], latched_addr, 1'b1/*GLOBAL tag*/, 1'b0/*WRITE*/, 1'b0};
                master_data_wr    <= latched_write_data; // data captured at WRITE time
                state             <= S_GW_START;
            end

         
            S_GW_START: begin
                if (!master_spi_busy) begin
                    master_start_tx <= 1'b1;
                    state           <= S_GW_WAIT;
                end
            end

            S_GW_WAIT: begin
                if (master_tx_done) begin
                    state <= S_GW_NEXT;
                end
            end

            S_GW_NEXT: begin
                if (gw_idx != 3'd7) begin
                    gw_idx <= gw_idx + 3'd1;
                    state  <= S_GW_BUILD;
                end else begin
                    state <= S_GW_DONE;
                end
            end

            S_GW_DONE: begin
                led_write_done_g <= 1'b1;
                timer_start      <= 1'b1;
                state            <= S_START_TIMER;
            end

            // --------------------------------------------------
            // Post-write 3s hold (single or global)
            S_START_TIMER: begin
                led_blue_out     <= 1'b1;
                led_write_done_g <= 1'b1;
                state            <= S_WAIT_TIMER;
            end

            S_WAIT_TIMER: begin
                led_blue_out     <= 1'b1;
                led_write_done_g <= 1'b1;
                if (timer_done) begin
                    led_blue_out <= 1'b0;
                    state        <= S_AWAIT_CMD;
                end
            end

            // --------------------------------------------------
            // READ display
            S_DISPLAY_READ: begin
                led_data_out <= master_data_rd;
                if (master_data_rd == 16'h0000) begin
                    led_red_out   <= 1'b1;
                    led_green_out <= 1'b0;
                end else begin
                    led_red_out   <= 1'b0;
                    led_green_out <= 1'b1;
                end
                state <= S_AWAIT_CMD;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
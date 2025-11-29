`default_nettype none

// ============================================================
// File: FLATTENED master_top.v
//
// **MODIFIED:** Removed all VIO-related logic.
// - Removed VIO wire declarations
// - Removed vio_0 instantiation
// - Simplified input logic to use buttons/switches directly
// ============================================================
module master_top (
    input  wire        clk,
    input  wire [15:0] sw,
    input  wire [3:0]  btn,
    output reg  [15:0] led,         // Changed to reg
    output wire [2:0]  RGB0,
    output wire [2:0]  RGB1,

    output reg         spi_sclk_out, // Changed to reg
    output reg         spi_mosi_out, // Changed to reg
    output reg  [7:0]  spi_cs_n_out, // Changed to reg
    input  wire        spi_miso_in
);

    // ============================================================
    // --- Wires from original master_top ---
    // ============================================================
    wire sys_reset = btn[0]; //
    
    // --- Wires/Regs connecting the two FSMs ---
    // (Must be reg, as they are driven by inlined always blocks)
    reg        master_start_tx;   //
    reg        master_spi_busy;   //
    reg        master_tx_done;    //
    reg [15:0] master_cmd_packet; //
    reg [15:0] master_data_wr;    //
    reg [15:0] master_data_rd;    //

    // --- Wires for RGB LEDs ---
    reg led_red_wire, led_blue_wire, led_green_wire, led_green_write_wire; //
    
    // --- VIO Wires Removed ---
    
    
    // ============================================================
    // --- Inlined logic from debounce (u_db_latch) ---
    //
    // ============================================================
    reg ctrl_btn_latch_db;
    reg  db_latch_sync0, db_latch_sync1;
    reg [31:0] db_latch_cnt;
    reg  db_latch_stable;

    // 2FF sync for latch button
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            db_latch_sync0 <= 1'b0;
            db_latch_sync1 <= 1'b0;
        end else begin
            db_latch_sync0 <= btn[2]; // Connected to btn_latch
            db_latch_sync1 <= db_latch_sync0;
        end
    end

    // counter-based debounce for latch button
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            db_latch_cnt           <= 32'd0;
            db_latch_stable        <= 1'b0;
            ctrl_btn_latch_db      <= 1'b0; //
        end else begin
            if (db_latch_sync1 != db_latch_stable) begin
                db_latch_cnt <= db_latch_cnt + 1;
                if (db_latch_cnt >= 250_000) begin //
                    db_latch_stable   <= db_latch_sync1;
                    ctrl_btn_latch_db <= db_latch_sync1;
                    db_latch_cnt      <= 32'd0;
                end
            end else begin
                db_latch_cnt <= 32'd0;
            end
        end
    end

    // ============================================================
    // --- Inlined logic from debounce (u_db_write_s) ---
    //
    // ============================================================
    reg ctrl_btn_write_s_db;
    reg  db_write_sync0, db_write_sync1;
    reg [31:0] db_write_cnt;
    reg  db_write_stable;

    // 2FF sync for write button
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            db_write_sync0 <= 1'b0;
            db_write_sync1 <= 1'b0;
        end else begin
            db_write_sync0 <= btn[3]; // Connected to btn_write_single
            db_write_sync1 <= db_write_sync0;
        end
    end

    // counter-based debounce for write button
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            db_write_cnt           <= 32'd0;
            db_write_stable        <= 1'b0;
            ctrl_btn_write_s_db    <= 1'b0; //
        end else begin
            if (db_write_sync1 != db_write_stable) begin
                db_write_cnt <= db_write_cnt + 1;
                if (db_write_cnt >= 250_000) begin //
                    db_write_stable      <= db_write_sync1;
                    ctrl_btn_write_s_db  <= db_write_sync1;
                    db_write_cnt         <= 32'd0;
                end
            end else begin
                db_write_cnt <= 32'd0;
            end
        end
    end

    // ============================================================
    // --- Inlined logic from debounce (u_db_read_s) ---
    //
    // ============================================================
    reg ctrl_btn_read_s_db;
    reg  db_read_sync0, db_read_sync1;
    reg [31:0] db_read_cnt;
    reg  db_read_stable;

    // 2FF sync for read button
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            db_read_sync0 <= 1'b0;
            db_read_sync1 <= 1'b0;
        end else begin
            db_read_sync0 <= btn[1]; // Connected to btn_read_single
            db_read_sync1 <= db_read_sync0;
        end
    end

    // counter-based debounce for read button
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            db_read_cnt           <= 32'd0;
            db_read_stable        <= 1'b0;
            ctrl_btn_read_s_db    <= 1'b0; //
        end else begin
            if (db_read_sync1 != db_read_stable) begin
                db_read_cnt <= db_read_cnt + 1;
                if (db_read_cnt >= 250_000) begin //
                    db_read_stable     <= db_read_sync1;
                    ctrl_btn_read_s_db <= db_read_sync1;
                    db_read_cnt        <= 32'd0;
                end
            end else begin
                db_read_cnt <= 32'd0;
            end
        end
    end
    
    // ============================================================
    // --- Inlined logic from timer_3sec (u_timer) ---
    //
    // ============================================================
    reg  ctrl_timer_start; //
    reg  ctrl_timer_done;  //
    reg  timer_running;    //
    reg [31:0] timer_cnt;  //
    localparam integer TIMER_TERMINAL = 100_000_000 * 3; //

    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            timer_running <= 1'b0;
            timer_cnt     <= 32'd0;
            ctrl_timer_done <= 1'b0;
        end else begin
            ctrl_timer_done <= 1'b0;
            if (ctrl_timer_start && !timer_running) begin //
                timer_running <= 1'b1;
                timer_cnt     <= 32'd0;
            end else if (timer_running) begin
                timer_cnt <= timer_cnt + 1;
                if (timer_cnt >= TIMER_TERMINAL-1) begin //
                    timer_running   <= 1'b0;
                    ctrl_timer_done <= 1'b1;  // one-cycle pulse
                end
            end
        end
    end

    // ============================================================
    // --- Inlined logic from system_control_fsm (u_control_fsm) ---
    //
    // ============================================================
    
    // --- Internal Regs ---
    reg [2:0] ctrl_latched_id;    //
    reg [7:0] ctrl_latched_addr;  //
    reg       ctrl_latched_global; //
    reg       ctrl_last_op_was_write; //
    reg       ctrl_global_mode;       //
    reg [2:0] ctrl_gw_idx;            //
    reg [15:0] ctrl_latched_write_data; //
    reg  [2:0]  ctrl_latched_id_out; // (disconnected)

    // --- States ---
    localparam [3:0]
        CTRL_S_IDLE         = 4'd0, //
        CTRL_S_LATCH_CMD    = 4'd1,
        CTRL_S_AWAIT_CMD    = 4'd2,
        CTRL_S_START_TX     = 4'd3,
        CTRL_S_WAIT_MASTER  = 4'd4,
        CTRL_S_DISPLAY_READ = 4'd5,
        CTRL_S_START_TIMER  = 4'd6,
        CTRL_S_WAIT_TIMER   = 4'd7,
        CTRL_S_GW_BUILD     = 4'd8,
        CTRL_S_GW_START     = 4'd9,
        CTRL_S_GW_WAIT      = 4'd10,
        CTRL_S_GW_NEXT      = 4'd11,
        CTRL_S_GW_DONE      = 4'd12;
    reg [3:0] ctrl_state; //

    // --- Input Mux Logic (VIO Removed) ---
    wire ctrl_latch_event = ctrl_btn_latch_db; //
    wire ctrl_write_event = ctrl_btn_write_s_db; //
    wire ctrl_read_event  = ctrl_btn_read_s_db; //
    
    wire [15:0] ctrl_latch_source = sw; //
    wire [15:0] ctrl_write_source = sw; //

    // --- Main Control FSM logic ---
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            ctrl_state             <= CTRL_S_IDLE;
            ctrl_latched_id        <= 3'd0;
            ctrl_latched_addr      <= 8'd0;
            ctrl_latched_global    <= 1'b0;
            ctrl_latched_id_out    <= 3'd0;

            master_start_tx   <= 1'b0;
            master_cmd_packet <= 16'h0000;
            master_data_wr    <= 16'h0000;

            led               <= 16'h0000; //
            led_red_wire      <= 1'b0;
            led_green_wire    <= 1'b0;
            led_blue_wire     <= 1'b0;
            led_green_write_wire <= 1'b0;
            
            ctrl_timer_start       <= 1'b0; //
            ctrl_last_op_was_write <= 1'b0;
            ctrl_global_mode       <= 1'b0;
            ctrl_gw_idx            <= 3'd0;
            ctrl_latched_write_data<= 16'h0000;
        end else begin
            // defaults
            master_start_tx  <= 1'b0;
            ctrl_timer_start <= 1'b0;
            led_green_write_wire <= 1'b0;

            case (ctrl_state)
            // --------------------------------------------------
            CTRL_S_IDLE: begin //
                led_red_wire  <= 1'b0;
                if (ctrl_latch_event) begin
                    ctrl_state <= CTRL_S_LATCH_CMD;
                end else if (ctrl_write_event) begin
                    ctrl_latched_write_data <= ctrl_write_source;
                    ctrl_last_op_was_write  <= 1'b1;

                    if (ctrl_latched_global) begin
                        // GLOBAL write
                        ctrl_global_mode  <= 1'b1;
                        ctrl_gw_idx       <= 3'd0;
                        led_blue_wire <= 1'b1;
                        ctrl_state        <= CTRL_S_GW_BUILD;
                    end else begin
                        // Single write
                        ctrl_global_mode   <= 1'b0;
                        master_cmd_packet  <= {2'b00, ctrl_latched_id, ctrl_latched_addr, 1'b0/*GLOBAL*/, 1'b0/*WRITE*/, 1'b0}; //
                        master_data_wr     <= ctrl_write_source;
                        led_blue_wire      <= 1'b1;
                        ctrl_state         <= CTRL_S_START_TX;
                    end
                end else if (ctrl_read_event) begin
                    // READ
                    ctrl_last_op_was_write  <= 1'b0;
                    ctrl_global_mode        <= 1'b0;
                    master_cmd_packet       <= {2'b00, ctrl_latched_id, ctrl_latched_addr, 1'b0/*GLOBAL*/, 1'b1/*READ*/, 1'b0}; //
                    master_data_wr          <= 16'h0000;
                    ctrl_state              <= CTRL_S_START_TX;
                end
            end

            // --------------------------------------------------
            CTRL_S_LATCH_CMD: begin //
                ctrl_latched_id        <= ctrl_latch_source[10:8];
                ctrl_latched_addr      <= ctrl_latch_source[7:0];
                ctrl_latched_global    <= ctrl_latch_source[15];
                ctrl_latched_id_out    <= ctrl_latch_source[10:8];
                led_red_wire           <= 1'b1;
                ctrl_state             <= CTRL_S_AWAIT_CMD;
            end

            // --------------------------------------------------
            CTRL_S_AWAIT_CMD: begin //
                led_red_wire <= 1'b0;
                if (ctrl_latch_event) begin
                    ctrl_state <= CTRL_S_LATCH_CMD;
                end else if (ctrl_write_event) begin
                    ctrl_latched_write_data <= ctrl_write_source;
                    ctrl_last_op_was_write  <= 1'b1;

                    if (ctrl_latched_global) begin
                        ctrl_global_mode  <= 1'b1;
                        ctrl_gw_idx       <= 3'd0;
                        led_blue_wire <= 1'b1;
                        ctrl_state        <= CTRL_S_GW_BUILD;
                    end else begin
                        ctrl_global_mode   <= 1'b0;
                        master_cmd_packet  <= {2'b00, ctrl_latched_id, ctrl_latched_addr, 1'b0/*GLOBAL*/, 1'b0/*WRITE*/, 1'b0}; //
                        master_data_wr     <= ctrl_write_source;
                        led_blue_wire      <= 1'b1;
                        ctrl_state         <= CTRL_S_START_TX;
                    end
                end else if (ctrl_read_event) begin
                    ctrl_last_op_was_write  <= 1'b0;
                    ctrl_global_mode        <= 1'b0;
                    master_cmd_packet       <= {2'b00, ctrl_latched_id, ctrl_latched_addr, 1'b0/*GLOBAL*/, 1'b1/*READ*/, 1'b0}; //
                    master_data_wr          <= 16'h0000;
                    ctrl_state              <= CTRL_S_START_TX;
                end
            end

            // --------------------------------------------------
            CTRL_S_START_TX: begin //
                if (!master_spi_busy) begin
                    master_start_tx <= 1'b1;
                    ctrl_state      <= CTRL_S_WAIT_MASTER;
                end
            end

            CTRL_S_WAIT_MASTER: begin //
                if (master_tx_done) begin
                    if (ctrl_last_op_was_write) begin
                        led_green_write_wire <= 1'b1;
                        ctrl_timer_start     <= 1'b1;
                        ctrl_state           <= CTRL_S_START_TIMER;
                    end else begin
                        ctrl_state <= CTRL_S_DISPLAY_READ;
                    end
                end
            end

            // --------------------------------------------------
            CTRL_S_GW_BUILD: begin //
                master_cmd_packet <= {2'b00, ctrl_gw_idx[2:0], ctrl_latched_addr, 1'b1/*GLOBAL tag*/, 1'b0/*WRITE*/, 1'b0};
                master_data_wr    <= ctrl_latched_write_data;
                ctrl_state        <= CTRL_S_GW_START;
            end
            
            CTRL_S_GW_START: begin //
                if (!master_spi_busy) begin
                    master_start_tx <= 1'b1;
                    ctrl_state      <= CTRL_S_GW_WAIT;
                end
            end

            CTRL_S_GW_WAIT: begin //
                if (master_tx_done) begin
                    ctrl_state <= CTRL_S_GW_NEXT;
                end
            end

            CTRL_S_GW_NEXT: begin //
                if (ctrl_gw_idx != 3'd7) begin
                    ctrl_gw_idx <= ctrl_gw_idx + 3'd1;
                    ctrl_state  <= CTRL_S_GW_BUILD;
                end else begin
                    ctrl_state <= CTRL_S_GW_DONE;
                end
            end

            CTRL_S_GW_DONE: begin //
                led_green_write_wire <= 1'b1;
                ctrl_timer_start     <= 1'b1;
                ctrl_state           <= CTRL_S_START_TIMER;
            end

            // --------------------------------------------------
            CTRL_S_START_TIMER: begin //
                led_blue_wire     <= 1'b1;
                led_green_write_wire <= 1'b1;
                ctrl_state        <= CTRL_S_WAIT_TIMER;
            end

            CTRL_S_WAIT_TIMER: begin //
                led_blue_wire     <= 1'b1;
                led_green_write_wire <= 1'b1;
                if (ctrl_timer_done) begin
                    led_blue_wire <= 1'b0;
                    ctrl_state    <= CTRL_S_AWAIT_CMD;
                end
            end

            // --------------------------------------------------
            CTRL_S_DISPLAY_READ: begin //
                led <= master_data_rd;
                if (master_data_rd == 16'h0000) begin
                    led_red_wire   <= 1'b1;
                    led_green_wire <= 1'b0;
                end else begin
                    led_red_wire   <= 1'b0;
                    led_green_wire <= 1'b1;
                end
                ctrl_state <= CTRL_S_AWAIT_CMD;
            end

            default: ctrl_state <= CTRL_S_IDLE;
            endcase
        end
    end

    
    // ============================================================
    // --- Inlined logic from spi_master_fsm (u_spi_master) ---
    //
    // ============================================================
    
    // --- SCLK Divider ---
    localparam integer SPI_SCLK_DIV = 8; //
    reg [15:0] spi_divcnt;
    wire       spi_tick = (spi_divcnt==0); //

    // --- Shift regs/counters ---
    reg [15:0] spi_shifter_out; //
    reg [15:0] spi_shifter_in;  //
    reg [5:0]  spi_bitcnt;      //
    reg        spi_active;      //

    // --- States ---
    localparam [2:0]
        SPI_ST_IDLE      = 3'd0, //
        SPI_ST_SEND_CMD  = 3'd1,
        SPI_ST_PREP_DATA = 3'd2,
        SPI_ST_DATA      = 3'd3,
        SPI_ST_DONE      = 3'd4;
    reg [2:0] spi_state; //

    // --- Decoded fields ---
    wire [2:0] spi_id   = master_cmd_packet[13:11]; //
    wire [7:0] spi_addr = master_cmd_packet[10:3];  //
    wire       spi_rd   = master_cmd_packet[1];     //

    // --- sclk edge detect ---
    wire spi_sclk_rise = spi_tick && (spi_sclk_out==1'b0); //
    wire spi_sclk_fall = spi_tick && (spi_sclk_out==1'b1); //

    // --- clock divider logic ---
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            spi_divcnt   <= SPI_SCLK_DIV-1;
            spi_sclk_out <= 1'b0;
        end else begin
            if (spi_active) begin
                if (spi_divcnt == 0) begin
                    spi_divcnt   <= SPI_SCLK_DIV-1;
                    spi_sclk_out <= ~spi_sclk_out;
                end else begin
                    spi_divcnt <= spi_divcnt - 1;
                end
            end else begin
                spi_divcnt   <= SPI_SCLK_DIV-1;
                spi_sclk_out <= 1'b0; // CPOL=0 idle low
            end
        end
    end

    // --- Main SPI FSM logic ---
    always @(posedge clk or posedge sys_reset) begin //
        if (sys_reset) begin
            spi_state         <= SPI_ST_IDLE;
            spi_active        <= 1'b0;
            master_spi_busy   <= 1'b0;
            master_tx_done    <= 1'b0;
            spi_cs_n_out      <= 8'hFF;
            spi_mosi_out      <= 1'b0;
            master_data_rd    <= 16'h0000;
            spi_shifter_out   <= 16'h0000;
            spi_shifter_in    <= 16'h0000;
            spi_bitcnt        <= 6'd0;
        end else begin
            master_tx_done <= 1'b0;
            // latch read data once per transaction
            if (spi_state == SPI_ST_DONE && spi_rd)
                master_data_rd <= spi_shifter_in; //

            case (spi_state)
            // ---------------------------------------------------------
            SPI_ST_IDLE: begin //
                master_spi_busy <= 1'b0;
                spi_active      <= 1'b0;
                spi_cs_n_out    <= 8'hFF;
                if (master_start_tx) begin //
                    spi_cs_n_out    <= ~(8'b1 << spi_id); //
                    master_spi_busy <= 1'b1;
                    spi_active      <= 1'b1;
                    spi_shifter_out <= master_cmd_packet; //
                    spi_bitcnt      <= 6'd16;
                    spi_mosi_out    <= master_cmd_packet[15]; //
                    spi_state       <= SPI_ST_SEND_CMD;
                end
            end

            // ---------------------------------------------------------
            SPI_ST_SEND_CMD: begin //
                if (spi_sclk_rise) begin
                    if (spi_bitcnt > 6'd1) begin
                        spi_bitcnt <= spi_bitcnt - 1;
                    end else if (spi_bitcnt == 6'd1) begin
                        spi_bitcnt <= 6'd16;
                        spi_state  <= SPI_ST_PREP_DATA;
                    end
                end

                if (spi_sclk_fall) begin
                    spi_shifter_out <= {spi_shifter_out[14:0], 1'b0};
                    spi_mosi_out    <= spi_shifter_out[14];
                end
            end

            // ---------------------------------------------------------
            SPI_ST_PREP_DATA: begin //
                if (spi_rd) begin
                    spi_shifter_in <= 16'h0000;
                    spi_mosi_out   <= 1'b0;
                end else begin
                    spi_shifter_out <= master_data_wr; //
                    spi_mosi_out    <= master_data_wr[15]; //
                end
                spi_state <= SPI_ST_DATA;
            end

            // ---------------------------------------------------------
            SPI_ST_DATA: begin //
                if (spi_rd) begin
                    if (spi_sclk_rise && spi_bitcnt != 0) begin
                        spi_shifter_in <= {spi_shifter_in[14:0], spi_miso_in}; //
                        spi_bitcnt     <= spi_bitcnt - 1;
                    end
                    if (spi_sclk_fall) begin 
                        spi_mosi_out <= 1'b0;
                    end
                end else begin
                    if (spi_sclk_rise && spi_bitcnt != 0) begin
                        spi_bitcnt <= spi_bitcnt - 1;
                    end
            
                    if (spi_sclk_fall) begin
                        if (spi_bitcnt == 6'd16) begin
                            spi_mosi_out <= spi_shifter_out[15];
                        end else begin
                            spi_shifter_out <= {spi_shifter_out[14:0], 1'b0};
                            spi_mosi_out    <= spi_shifter_out[14];
                        end
                    end
                end

                if (spi_bitcnt == 0 && spi_sclk_out==1'b0 && spi_tick) begin
                    spi_active   <= 1'b0;
                    spi_cs_n_out <= 8'hFF;
                    spi_state    <= SPI_ST_DONE;
                end
            end

            // ---------------------------------------------------------
            SPI_ST_DONE: begin //
                master_spi_busy <= 1'b0;
                master_tx_done  <= 1'b1;
                spi_state       <= SPI_ST_IDLE;
            end

            default: spi_state <= SPI_ST_IDLE;
            endcase
        end
    end
    
    // ============================================================
    // --- VIO Core Instantiation (REMOVED) ---
    // ============================================================
 

    // ============================================================
    // --- Final RGB Assigns (Unchanged) ---
    //
    // ============================================================
    assign RGB0[0] = led_red_wire;
    assign RGB0[1] = led_green_wire;
    assign RGB0[2] = led_blue_wire;
    assign RGB1[0] = 1'b0;
    assign RGB1[1] = led_green_write_wire;
    assign RGB1[2] = 1'b0;
    
endmodule

`default_nettype wire
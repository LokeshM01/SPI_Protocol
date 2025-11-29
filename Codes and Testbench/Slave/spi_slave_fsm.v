`default_nettype none
module spi_slave_fsm #(
    parameter [2:0] MY_ID = 3'd0
)(
    input  wire clk,
    input  wire rst,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n,
    
    // debug outputs
    output wire        led_we_pulse,
    output reg  [15:0] led_data_out 
);

    // Sync external SCLK and CS_N into clk domain
    reg sclk_d0, sclk_d1;
    reg cs_d0,   cs_d1;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_d0 <= 1'b0;
            sclk_d1 <= 1'b0;
            cs_d0   <= 1'b1;
            cs_d1   <= 1'b1;
        end else begin
            sclk_d0 <= sclk;
            sclk_d1 <= sclk_d0;
            cs_d0   <= cs_n;
            cs_d1   <= cs_d0;
        end
    end

    wire cs_active = ~cs_d1;
    wire sclk_rise = (sclk_d1==1'b0) && (sclk_d0==1'b1);
    wire sclk_fall = (sclk_d1==1'b1) && (sclk_d0==1'b0);

    // RAM
    reg        ram_we, ram_re;
    reg [7:0]  ram_waddr, ram_raddr;
    reg [15:0] ram_din;
    wire[15:0] ram_dout;

    slave_ram u_ram (
        .clk        (clk),
        .we         (ram_we),
        .re         (ram_re),
        .write_addr (ram_waddr),
        .read_addr  (ram_raddr),
        .data_in    (ram_din),
        .data_out   (ram_dout)
    );

    // Shifters/state
    reg [15:0] cmd_shift;
    reg [15:0] data_shift_in;
    reg [15:0] data_shift_out;
    reg [5:0]  bitcnt;
    reg        is_read;

    // temporaries to avoid NB-assign issues
    reg [15:0] next_cmd;
    reg [15:0] next_data;

    localparam [2:0]
        S_IDLE      = 3'd0,
        S_CMD       = 3'd1,
        S_DATA      = 3'd2,
        S_DATA_PREP = 3'd3;

    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= S_IDLE;
            bitcnt        <= 6'd0;
            miso          <= 1'b0;
            ram_we        <= 1'b0;
            ram_re        <= 1'b0;
            ram_waddr     <= 8'h00;
            ram_raddr     <= 8'h00;
            ram_din       <= 16'h0000;
            cmd_shift     <= 16'h0000;
            data_shift_in <= 16'h0000;
            data_shift_out<= 16'h0000;
            is_read       <= 1'b0;
            next_cmd      <= 16'h0000;
            next_data     <= 16'h0000;
            led_data_out  <= 16'h0000;
        end else begin
            // default: no RAM access unless asserted in state machine
            ram_we <= 1'b0;
            ram_re <= 1'b0;

            case (state)
            // ---------------------------------------------------------
            // IDLE: wait for CS_N to go low
            // ---------------------------------------------------------
            S_IDLE: begin
                miso <= 1'b0;
                if (cs_active) begin
                    state     <= S_CMD;
                    bitcnt    <= 6'd16;      // 16 command bits
                    cmd_shift <= 16'h0000;
                end
            end

            // ---------------------------------------------------------
            // S_CMD: shift in 16-bit command on SCLK rising edges
            // ---------------------------------------------------------
            S_CMD: begin
                if (!cs_active) begin
                    state <= S_IDLE;
                end else if (sclk_rise) begin
                    // Shift MOSI into command shift register
                    cmd_shift <= {cmd_shift[14:0], mosi};

                    if (bitcnt > 6'd1) begin
                        // Not the last command bit yet
                        bitcnt <= bitcnt - 1;

                    end else if (bitcnt == 6'd1) begin
                        // This rising edge is the LAST command bit.
                        // Build full command word safely.
                        next_cmd   = {cmd_shift[14:0], mosi};
                        is_read    <= next_cmd[1];
                        ram_waddr  <= next_cmd[10:3];
                        ram_raddr  <= next_cmd[10:3];

                        if (next_cmd[1]) begin
                            // READ command
                            ram_re <= 1'b1;   // 1-cycle read enable
                            bitcnt <= 6'd16;  // 16 data bits to follow
                            state  <= S_DATA_PREP;
                        end else begin
                            // WRITE command
                            data_shift_in <= 16'h0000;
                            bitcnt        <= 6'd16;
                            state         <= S_DATA;
                        end
                    end
                end
            end

            // ---------------------------------------------------------
            // S_DATA_PREP: latch RAM output, present D15 on MISO
            // ---------------------------------------------------------
            S_DATA_PREP: begin
                data_shift_out <= ram_dout;
                miso           <= ram_dout[15]; // D15 on the line
                state          <= S_DATA;
            end

            // ---------------------------------------------------------
            // S_DATA: read or write 16 bits of data
            // ---------------------------------------------------------
            S_DATA: begin
                if (!cs_active) begin
                    miso  <= 1'b0;
                    state <= S_IDLE;
                end else if (is_read) begin
                    // ---------- READ PATH ----------
                    // Master samples @ rising; slave changes MISO @ falling
                    if (sclk_fall) begin
                        miso           <= data_shift_out[15];
                        data_shift_out <= {data_shift_out[14:0], 1'b0};
                    end
                    if (sclk_rise) begin
                        if (bitcnt != 0) bitcnt <= bitcnt - 1;
                    end
                    if (bitcnt == 0) begin
                        miso  <= 1'b0;
                        state <= S_IDLE;
                    end
                end else begin
                    // ---------- WRITE PATH ----------
                    if (sclk_rise) begin
                        data_shift_in <= {data_shift_in[14:0], mosi};
                        if (bitcnt != 0) bitcnt <= bitcnt - 1;

                        if (bitcnt == 6'd1) begin
                            // Last data bit just captured
                            next_data    = {data_shift_in[14:0], mosi};
                            ram_din      <= next_data;
                            ram_we       <= 1'b1;
                            led_data_out <= next_data; // debug
                        end
                    end
                    if (bitcnt == 0) begin
                        miso  <= 1'b0;
                        state <= S_IDLE;
                    end
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

    assign led_we_pulse = ram_we;

endmodule
`default_nettype wire

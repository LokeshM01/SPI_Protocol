`default_nettype none
module spi_master_fsm #(
    parameter integer SCLK_DIV = 8  // clk/(2*SCLK_DIV) ~= SCLK freq
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start_tx,
    input  wire [15:0] cmd_packet_in,
    input  wire [15:0] data_out_in,   // data to write (when READ=0)
    output reg         spi_busy,
    output reg         tx_done,
    output reg [15:0]  data_read_out, // data read (when READ=1)

    output reg         sclk_out,
    output reg         mosi_out,
    input  wire        miso_in,
    output reg  [7:0]  cs_n_out       // active-low chip selects
);

    // Decode fields
    wire [2:0] id   = cmd_packet_in[13:11];
    wire [7:0] addr = cmd_packet_in[10:3];
    wire       rd   = cmd_packet_in[1];

    // SCLK divider
    reg [15:0] divcnt;
    wire       tick = (divcnt==0);

    // Shift regs/counters
    reg [15:0] shifter_out;
    reg [15:0] shifter_in;
    reg [5:0]  bitcnt;
    reg        active;

    // state
    localparam [2:0]
        ST_IDLE      = 3'd0,
        ST_SEND_CMD  = 3'd1,
        ST_PREP_DATA = 3'd2,
        ST_DATA      = 3'd3,
        ST_DONE      = 3'd4;
    reg [2:0] state;

    // sclk edge detect (Mode 0: CPOL=0, CPHA=0)
    wire sclk_rise = tick && (sclk_out==1'b0);
    wire sclk_fall = tick && (sclk_out==1'b1);

    // clock divider
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            divcnt   <= SCLK_DIV-1;
            sclk_out <= 1'b0;
        end else begin
            if (active) begin
                if (divcnt == 0) begin
                    divcnt   <= SCLK_DIV-1;
                    sclk_out <= ~sclk_out;
                end else begin
                    divcnt <= divcnt - 1;
                end
            end else begin
                divcnt   <= SCLK_DIV-1;
                sclk_out <= 1'b0; // CPOL=0 idle low
            end
        end
    end

    // main FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= ST_IDLE;
            active        <= 1'b0;
            spi_busy      <= 1'b0;
            tx_done       <= 1'b0;
            cs_n_out      <= 8'hFF;
            mosi_out      <= 1'b0;
            data_read_out <= 16'h0000;
            shifter_out   <= 16'h0000;
            shifter_in    <= 16'h0000;
            bitcnt        <= 6'd0;
        end else begin
            tx_done <= 1'b0;

            // latch read data once per transaction
            if (state == ST_DONE && rd)
                data_read_out <= shifter_in;

            case (state)
            // ---------------------------------------------------------
            // ST_IDLE: wait for start_tx
            // ---------------------------------------------------------
            ST_IDLE: begin
                spi_busy <= 1'b0;
                active   <= 1'b0;
                cs_n_out <= 8'hFF;
                if (start_tx) begin
                    // assert CS for selected ID
                    cs_n_out    <= ~(8'b1 << id);
                    spi_busy    <= 1'b1;
                    active      <= 1'b1;
                    shifter_out <= cmd_packet_in;
                    bitcnt      <= 6'd16;      // 16 command bits
                    // put first MOSI bit before first rising edge
                    mosi_out    <= cmd_packet_in[15];
                    state       <= ST_SEND_CMD;
                end
            end

            // ---------------------------------------------------------
            // ST_SEND_CMD: shift out 16-bit command
            // ---------------------------------------------------------
            ST_SEND_CMD: begin
                // Mode 0: change @ falling, sample @ rising
                if (sclk_rise) begin
                    if (bitcnt > 6'd1) begin
                        // not last cmd bit yet
                        bitcnt <= bitcnt - 1;
                    end else if (bitcnt == 6'd1) begin
                        // this rising edge is LAST command bit
                        bitcnt <= 6'd16;     // prepare for 16 data bits
                        state  <= ST_PREP_DATA;
                    end
                end

                if (sclk_fall) begin
                    // shift next MOSI bit on falling edges
                    shifter_out <= {shifter_out[14:0], 1'b0};
                    mosi_out    <= shifter_out[14];
                end
            end

            // ---------------------------------------------------------
            // ST_PREP_DATA: one-tick prep between cmd and data
            // ---------------------------------------------------------
            ST_PREP_DATA: begin
                if (rd) begin
                    // READ: clear input shifter, drive MOSI low
                    shifter_in <= 16'h0000;
                    mosi_out   <= 1'b0;
                end else begin
                    // WRITE: load data to send, preload MSB
                    shifter_out <= data_out_in;
                    mosi_out    <= data_out_in[15];
                end
                state <= ST_DATA;
            end

            // ---------------------------------------------------------
            // ST_DATA: 16-bit data phase (read or write)
            // ---------------------------------------------------------
            ST_DATA: begin
                if (rd) begin
                    // READ: sample MISO on rising edges
                    if (sclk_rise && bitcnt != 0) begin
                        shifter_in <= {shifter_in[14:0], miso_in};
                        bitcnt     <= bitcnt - 1;
                    end
                    if (sclk_fall) begin
                        mosi_out <= 1'b0; // keep MOSI low in read
                    end
                end else begin
                    // WRITE: shift out data on MOSI @ falling
                    // - bitcnt starts at 16 when data phase begins
                    // - we want the FIRST data rising edge to see D15
                    if (sclk_rise && bitcnt != 0) begin
                        bitcnt <= bitcnt - 1;
                    end
            
                    if (sclk_fall) begin
                        if (bitcnt == 6'd16) begin
                            // First data-phase falling edge:
                            // keep D15 on MOSI, don't shift yet
                            mosi_out <= shifter_out[15];
                        end else begin
                            // Normal behaviour: shift next bit out
                            shifter_out <= {shifter_out[14:0], 1'b0};
                            mosi_out    <= shifter_out[14];
                        end
                    end
                end

                // finish when 16 data bits are done and SCLK is back low
                if (bitcnt == 0 && sclk_out==1'b0 && tick) begin
                    active   <= 1'b0;
                    cs_n_out <= 8'hFF;
                    state    <= ST_DONE;
                end
            end

            // ---------------------------------------------------------
            // ST_DONE: 1-cycle "transaction complete" pulse
            // ---------------------------------------------------------
            ST_DONE: begin
                spi_busy <= 1'b0;
                tx_done  <= 1'b1;
                state    <= ST_IDLE;
            end

            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire

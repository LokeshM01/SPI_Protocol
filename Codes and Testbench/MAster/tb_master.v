`timescale 1ns / 1ps

// ============================================================
// File: tb_master_top.v
//
// **FIXED (v2):** Replaced second illegal 'wire' declaration
//               (is_read) with procedural assignment to
//               'tb_slave_is_read'
// ============================================================
module tb_master_top;

    // ============================================================
    // Testbench Signals
    // ============================================================

    // --- Inputs to DUT ---
    reg        clk;
    reg [15:0] sw;
    reg [3:0]  btn;
    reg        spi_miso_in; // Driven by our slave model

    // --- Outputs from DUT ---
    wire [15:0] led;
    wire [2:0]  RGB0;
    wire [2:0]  RGB1;
    wire        spi_sclk_out;
    wire        spi_mosi_out;
    wire [7:0]  spi_cs_n_out;

    // --- Testbench Parameters ---
    localparam integer CLK_PERIOD = 10; // 10ns = 100MHz
    // Debounce is 250,000 cycles. @ 10ns, this is 2,500,000 ns = 2.5ms
    localparam integer DEBOUNCE_WAIT = 260_000; // Wait 2.6ms

    // ============================================================
    // Instantiate the Design Under Test (DUT)
    // ============================================================
    master_top uut (
        .clk           (clk),
        .sw            (sw),
        .btn           (btn),
        .led           (led),
        .RGB0          (RGB0),
        .RGB1          (RGB1),
        .spi_sclk_out  (spi_sclk_out),
        .spi_mosi_out  (spi_mosi_out),
        .spi_cs_n_out  (spi_cs_n_out),
        .spi_miso_in   (spi_miso_in)
    );

    // ============================================================
    // Clock Generation
    // ============================================================
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ============================================================
    // Helper Task for Button Presses
    // ============================================================
    task pulse_btn;
        input integer idx;
        begin
            $display("[%0t ns] Pulsing button btn[%0d]", $time, idx);
            btn[idx] = 1'b1;
            #(CLK_PERIOD * DEBOUNCE_WAIT); // Wait > 2.5ms for debounce
            btn[idx] = 1'b0;
            #(CLK_PERIOD * 1000); // Wait for FSM to settle
        end
    endtask

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin
        // --- 1. Initialization and Reset ---
        $display("[%0t ns] Starting Testbench...", $time);
        clk         = 0;
        sw          = 16'h0000;
        btn         = 4'h0;
        spi_miso_in = 1'b0;

        // Apply reset (btn[0] is sys_reset)
        btn[0] = 1'b1;
        #(CLK_PERIOD * 20);
        btn[0] = 1'b0;
        
        // Wait for reset to propagate
        #(CLK_PERIOD * 10);
        
        // --- 2. TEST 1: Latch and Write Single ---
        $display("[%0t ns] TEST 1: Latch and Write Single", $time);
        
        // 2a. Latch command (ID=1, ADDR=0x1A, GLOBAL=0)
        // sw = 16'b 0_001_00011010_00000 = 16'h11A0
        sw = 16'h11A0;
        pulse_btn(2); // Press btn[2] (latch)
        
        // 2b. Set data and write
        sw = 16'hBEEF;
        pulse_btn(3); // Press btn[3] (write)

        // Wait for transaction and 3s timer to finish
        // 3s = 3,000,000,000 ns. Add 100ms margin.
        #(3_100_000_000);
        
        // --- 3. TEST 2: Read Single ---
        $display("[%0t ns] TEST 2: Read Single", $time);
        // Command (ID=1, ADDR=0x1A) is still latched from TEST 1
        pulse_btn(1); // Press btn[1] (read)
        
        #(CLK_PERIOD * 1000); // Wait for read to complete
        $display("[%0t ns] Read data on LED: %h (Expected C0DE)", $time, led);
        
        // --- 4. TEST 3: Latch and Global Write ---
        $display("[%0t ns] TEST 3: Latch and Global Write", $time);
        
        // 4a. Latch command (ID=X, ADDR=0x05, GLOBAL=1)
        // sw = 16'b 1_000_00000101_00000 = 16'h8005
        sw = 16'h8005;
        pulse_btn(2); // Press btn[2] (latch)
        
        // 4b. Set data and write
        sw = 16'hFACE;
        pulse_btn(3); // Press btn[3] (write)
        
        // Wait for all 8 transactions + 3s timer
        #(3_500_000_000); 
        
        // --- 5. TEST 4: Read back from Global Write ---
        $display("[%0t ns] TEST 4: Read back from Global Write", $time);
        
        // 5a. Latch new command (ID=7, ADDR=0x05, GLOBAL=0)
        // sw = 16'b 0_111_00000101_00000 = 16'h3805
        sw = 16'h3805;
        pulse_btn(2); // Press btn[2] (latch)

        // 5b. Read from ID 7
        pulse_btn(1); // Press btn[1] (read)
        #(CLK_PERIOD * 1000);
        $display("[%0t ns] Read data from ID 7: %h (Expected FACE)", $time, led);

        // 5c. Latch new command (ID=0, ADDR=0x05, GLOBAL=0)
        // sw = 16'b 0_000_00000101_00000 = 16'h0005
        sw = 16'h0005;
        pulse_btn(2); // Press btn[2] (latch)
        
        // 5d. Read from ID 0
        pulse_btn(1); // Press btn[1] (read)
        #(CLK_PERIOD * 1000);
        $display("[%0t ns] Read data from ID 0: %h (Expected FACE)", $time, led);
        
        $display("[%0t ns] --- TESTBENCH COMPLETE ---", $time);
        $finish;
    end
    
    // ============================================================
    // Behavioral SPI Slave Model (Mode 0)
    // ============================================================
    
    // This slave simulates a memory block for all 8 slave IDs
    reg [15:0] slave_mem [255:0]; // 256 addresses
    
    // *** FIX 1 (v1): ADDED reg declarations for procedural assignment ***
    reg [7:0]  tb_slave_addr;
    reg [15:0] tb_slave_data;
    reg        tb_slave_is_read;
    reg        tb_slave_is_write;
    
    // This register handles all shifting (CMD and DATA)
    reg [31:0] slave_shift_reg;
    reg [5:0]  slave_bit_count; // Counts from 32 down to 0
    
    // Detect SCLK edges
    reg  sclk_d1, sclk_d2;
    wire sclk_rise_edge, sclk_fall_edge;
    
    // Detect CS assertion
    wire slave_cs_active = (spi_cs_n_out != 8'hFF);
    reg  slave_cs_d1;
    wire slave_cs_asserted = slave_cs_active && !slave_cs_d1;

    // Initialize slave memory
    initial begin
        // Pre-load the data for the READ test (Test 2)
        slave_mem[8'h1A] = 16'hC0DE; 
        slave_mem[8'h05] = 16'h1111; // Default value
    end

    // SCLK edge detection logic
    always @(posedge clk) begin
        sclk_d1 <= spi_sclk_out;
        sclk_d2 <= sclk_d1;
    end
    assign sclk_rise_edge = (sclk_d1 == 1'b1) && (sclk_d2 == 1'b0);
    assign sclk_fall_edge = (sclk_d1 == 1'b0) && (sclk_d2 == 1'b1);
    
    // CS assertion detection logic
    always @(posedge clk) begin
        slave_cs_d1 <= slave_cs_active;
    end

    // Slave main logic
    always @(posedge clk) begin
        if (!slave_cs_active) begin
            spi_miso_in <= 1'b0; // Not high-Z, but '0' for simulation
            slave_bit_count <= 32;
        end
        else begin // slave_cs_active
            
            // On CS assertion, reset bit count
            if (slave_cs_asserted) begin
                slave_bit_count <= 32;
                slave_shift_reg <= 32'b0;
            end

            // 1. Slave SAMPLES MOSI on SCLK RISING edge
            //    (Master drives on FALL, so data is stable on RISE)
            if (sclk_rise_edge) begin
                if (slave_bit_count > 0) begin
                    slave_shift_reg <= {slave_shift_reg[30:0], spi_mosi_out};
                    slave_bit_count <= slave_bit_count - 1;
                end
                
                // *** FIX 2 (v1): Replaced illegal 'wire' declarations ***
                // Just as command phase ends (bit 16 rising edge)
                if (slave_bit_count == 17) begin 
                    // On the *next* clock (when bit_count==16), 
                    // the command will be in shift_reg[31:16]
                    // We can pre-load the data for the read.
                    tb_slave_addr    = {slave_shift_reg[25:19], spi_mosi_out}; // Get address
                    tb_slave_is_read = slave_shift_reg[1+16]; // Check READ bit
                    
                    if (tb_slave_is_read) begin
                        $display("[%0t ns] SLAVE: Detected READ from addr %h. Loading %h", $time, tb_slave_addr, slave_mem[tb_slave_addr]);
                        // Load data into lower half of shifter, ready to be shifted out
                        slave_shift_reg[15:0] <= slave_mem[tb_slave_addr];
                    end
                end
            end

            // 2. Slave DRIVES MISO on SCLK FALLING edge
            //    (Master samples on RISE, so we drive on FALL)
            if (sclk_fall_edge) begin
                if (slave_bit_count < 16) begin // We are in the DATA phase
                    // *** FIX 1 (v2): Replaced illegal 'wire' and used correct variable ***
                    tb_slave_is_read = slave_shift_reg[1+16]; // Check if the command (now in upper bits) was a READ
                    if (tb_slave_is_read) begin
                        spi_miso_in <= slave_shift_reg[15]; // Drive MSB of data
                        // Shift the data for the *next* fall edge
                        slave_shift_reg[15:0] <= {slave_shift_reg[14:0], 1'b0}; 
                    end
                end
            end

            // *** FIX 3 (v1): Replaced illegal 'wire' declarations ***
            // 3. Handle WRITE operation (store data at end of transaction)
            //    This happens on the *last* rising edge (bit_count goes from 1 to 0)
            if (sclk_rise_edge && slave_bit_count == 1) begin
                tb_slave_is_write = !slave_shift_reg[1+16];
                if (tb_slave_is_write) begin
                    tb_slave_addr = slave_shift_reg[26:19];
                    tb_slave_data = {slave_shift_reg[14:0], spi_mosi_out};
                    $display("[%0t ns] SLAVE: Detected WRITE to addr %h with data %h", $time, tb_slave_addr, tb_slave_data);
                    slave_mem[tb_slave_addr] <= tb_slave_data;
                end
            end
        end
    end

endmodule
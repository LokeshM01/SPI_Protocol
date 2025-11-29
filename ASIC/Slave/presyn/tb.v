`timescale 1ns / 1ps
`default_nettype wire

// ============================================================
// Testbench Module
// ============================================================
module tb;

    // --- Parameters ---
    localparam CLK_PERIOD    = 10; // [cite_start] 100 MHz system clock [cite: 5]
    localparam SPI_PERIOD    = 40; // 25 MHz SPI clock (must be > 2*CLK_PERIOD)

    // --- TB Signals ---
    reg clk;
    reg rst_btn;
    reg spi_sclk_in;
    reg spi_mosi_in;
    reg spi_cs_n_in;
    reg [15:0] read_back_data; // Moved from 'initial' block for Verilog-2001 compatibility

    wire spi_miso_out;
    wire [15:0] led;

    // --- Instantiate the Device Under Test (DUT) ---
    slave u_dut (
        .clk           (clk),
        .rst_btn       (rst_btn),
        .spi_sclk_in   (spi_sclk_in),
        .spi_mosi_in   (spi_mosi_in),
        .spi_cs_n_in   (spi_cs_n_in),
        .spi_miso_out  (spi_miso_out),
        .led           (led)
    );

    // --- Clock Generator (100 MHz) ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // --- Reset Task ---
    task reset_dut;
        begin
            $display("[%0t] --- Applying Reset ---", $time);
            rst_btn     = 1; // Active high reset
            spi_cs_n_in = 1; // SPI idle
            spi_sclk_in = 0;
            spi_mosi_in = 0;
            #(CLK_PERIOD * 5);
            rst_btn = 0;
            #(CLK_PERIOD);
            $display("[%0t] --- Reset Released ---", $time);
        end
    endtask

    // --- SPI Write Task ---
    // Simulates a master writing 16 bits of data to an 8-bit address
    task spi_write;
        input [7:0]  addr;
        input [15:0] data_w;
        reg [15:0] command;
        integer i; // Declare loop variable here for Verilog-2001

        begin
            command = 16'h0000;
            command[10:3] = addr;    // [cite_start] Set address [cite: 44]
            command[1]    = 1'b0;    // [cite_start] 0 = Write [cite: 43]

            // 1. Assert CS_N
            spi_sclk_in = 0;
            spi_cs_n_in = 0;
            #(SPI_PERIOD);

            // 2. Send 16-bit Command
            for (i = 15; i >= 0; i = i - 1) begin // Use 'i' instead of 'integer i'
                spi_mosi_in = command[i]; // Data valid before rising edge
                #(SPI_PERIOD / 2);
                spi_sclk_in = 1;         // [cite_start] Rising edge (slave samples) [cite: 40]
                #(SPI_PERIOD / 2);
                spi_sclk_in = 0;         // Falling edge
            end

            // 3. Send 16-bit Data
            for (i = 15; i >= 0; i = i - 1) begin // Use 'i' instead of 'integer i'
                spi_mosi_in = data_w[i];
                #(SPI_PERIOD / 2);
                spi_sclk_in = 1;         // [cite_start] Rising edge (slave samples) [cite: 60]
                #(SPI_PERIOD / 2);
                spi_sclk_in = 0;
            end

            // 4. De-assert CS_N
            spi_cs_n_in = 1;
            spi_mosi_in = 0;
            #(CLK_PERIOD * 5); // Wait a few system clocks
            $display("[%0t] TB: SPI WRITE: Addr=0x%h, Data=0x%h. (LED should show 0x%h)", 
                $time, addr, data_w, data_w);
        end
    endtask

    // --- SPI Read Task ---
    // Simulates a master reading 16 bits of data from an 8-bit address
    task spi_read;
        input  [7:0]  addr;
        output [15:0] data_r;
        reg [15:0] command;
        integer i; // Declare loop variable here for Verilog-2001

        begin
            command = 16'h0000;
            command[10:3] = addr;    // [cite_start] Set address [cite: 44]
            command[1]    = 1'b1;    // [cite_start] 1 = Read [cite: 43]
            data_r = 16'h0000;

            // 1. Assert CS_N
            spi_sclk_in = 0;
            spi_cs_n_in = 0;
            #(SPI_PERIOD);

            // 2. Send 16-bit Command
            for (i = 15; i >= 0; i = i - 1) begin // Use 'i' instead of 'integer i'
                spi_mosi_in = command[i];
                #(SPI_PERIOD / 2);
                spi_sclk_in = 1;
                #(SPI_PERIOD / 2);
                spi_sclk_in = 0;
            end

            spi_mosi_in = 0; // Master is quiet during read

            // 3. Read 16-bit Data
            // [cite_start] Slave changes on FALL [cite: 56][cite_start], Master samples on RISE [cite: 57]
            for (i = 15; i >= 0; i = i - 1) begin // Use 'i' instead of 'integer i'
                #(SPI_PERIOD / 2);
                spi_sclk_in = 1;         // Rising edge
                data_r[i] = spi_miso_out; // Sample MISO
                #(SPI_PERIOD / 2);
                spi_sclk_in = 0;         // Falling edge
            end

            // 4. De-assert CS_N
            spi_cs_n_in = 1;
            #(CLK_PERIOD * 5); // Wait
            $display("[%0t] TB: SPI READ:  Addr=0x%h, Data=0x%h", $time, addr, data_r);
        end
    endtask


    // --- Test Sequence ---
    initial begin
        // reg [15:0] read_back_data; // <-- Removed from here
        
        // 1. Initialize and Reset
        reset_dut;
        #(CLK_PERIOD * 10);

        // 2. Test Write
        $display("--- Test 1: Writing 0xAAAA to Addr 0x05 ---");
        spi_write(8'h05, 16'hAAAA);
        #(CLK_PERIOD * 10); // [cite_start] Give time for LED latch to update [cite: 8]

        // 3. Test Read
        $display("--- Test 2: Reading from Addr 0x05 ---");
        spi_read(8'h05, read_back_data);
        #(CLK_PERIOD * 10);

        // 4. Check Read Data
        if (read_back_data == 16'hAAAA)
            $display(">>> PASS: Read data (0x%h) matches written data (0xAAAA)", read_back_data);
        else
            $display(">>> FAIL: Read data (0x%h) != 0xAAAA", read_back_data);
        #(CLK_PERIOD * 20);

        // 5. Test Write to another address
        $display("--- Test 3: Writing 0x1234 to Addr 0x42 ---");
        spi_write(8'h42, 16'h1234);
        #(CLK_PERIOD * 10);

        // 6. Read back from new address
        $display("--- Test 4: Reading from Addr 0x42 ---");
        spi_read(8'h42, read_back_data);
        #(CLK_PERIOD * 10);
        
        if (read_back_data == 16'h1234)
            $display(">>> PASS: Read data (0x%h) matches written data (0x1234)", read_back_data);
        else
            $display(">>> FAIL: Read data (0x%h) != 0x1234", read_back_data);
        #(CLK_PERIOD * 20);

        // 7. Read from original address (check persistence)
        $display("--- Test 5: Reading from Addr 0x05 again ---");
        spi_read(8'h05, read_back_data);
        #(CLK_PERIOD * 10);

        if (read_back_data == 16'hAAAA)
            $display(">>> PASS: Read data (0x%h) persists", read_back_data);
        else
            $display(">>> FAIL: Read data (0x%h) did not persist", read_back_data);
        #(CLK_PERIOD * 20);

        // 8. End simulation
        $display("--- Test Sequence Complete ---");
        $finish;
    end

endmodule

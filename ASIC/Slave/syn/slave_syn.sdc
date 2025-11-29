# ####################################################################

#  Created by Genus(TM) Synthesis Solution 21.19-s055_1 on Fri Nov 14 18:42:21 IST 2025

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1000fF
set_units -time 1000ps

# Set the current design
current_design slave

create_clock -name "clk" -period 100.0 -waveform {0.0 50.0} [get_ports clk]
set_load -pin_load 0.1 [get_ports spi_miso_out]
set_load -pin_load 0.1 [get_ports {led[15]}]
set_load -pin_load 0.1 [get_ports {led[14]}]
set_load -pin_load 0.1 [get_ports {led[13]}]
set_load -pin_load 0.1 [get_ports {led[12]}]
set_load -pin_load 0.1 [get_ports {led[11]}]
set_load -pin_load 0.1 [get_ports {led[10]}]
set_load -pin_load 0.1 [get_ports {led[9]}]
set_load -pin_load 0.1 [get_ports {led[8]}]
set_load -pin_load 0.1 [get_ports {led[7]}]
set_load -pin_load 0.1 [get_ports {led[6]}]
set_load -pin_load 0.1 [get_ports {led[5]}]
set_load -pin_load 0.1 [get_ports {led[4]}]
set_load -pin_load 0.1 [get_ports {led[3]}]
set_load -pin_load 0.1 [get_ports {led[2]}]
set_load -pin_load 0.1 [get_ports {led[1]}]
set_load -pin_load 0.1 [get_ports {led[0]}]
set_clock_gating_check -setup 0.0 
set_max_transition 0.6 [current_design]
set_max_capacitance 0.1 [get_ports clk]
set_max_capacitance 0.1 [get_ports rst_btn]
set_max_capacitance 0.1 [get_ports spi_sclk_in]
set_max_capacitance 0.1 [get_ports spi_mosi_in]
set_max_capacitance 0.1 [get_ports spi_cs_n_in]
set_operating_conditions -library tcbn65gpluswc_ccs WCCOM
set_wire_load_mode "segmented"
set_clock_latency -max 0.25 [get_clocks clk]
set_clock_uncertainty -setup 15.0 [get_clocks clk]
set_clock_uncertainty -hold 15.0 [get_clocks clk]


# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s012
#

set tcl_prompt1 {puts -nonewline "xcelium> "}
set tcl_prompt2 {puts -nonewline "> "}
set vlog_format %h
set vhdl_format %v
set real_precision 6
set display_unit auto
set time_unit module
set heap_garbage_size -200
set heap_garbage_time 0
set assert_report_level note
set assert_stop_level error
set autoscope yes
set assert_1164_warnings yes
set pack_assert_off {}
set severity_pack_assert_off {note warning}
set assert_output_stop_level failed
set tcl_debug_level 0
set relax_path_name 1
set vhdl_vcdmap XX01ZX01X
set intovf_severity_level ERROR
set probe_screen_format 0
set rangecnst_severity_level ERROR
set textio_severity_level ERROR
set vital_timing_checks_on 1
set vlog_code_show_force 0
set assert_count_attempts 1
set tcl_all64 false
set tcl_runerror_exit false
set assert_report_incompletes 0
set show_force 1
set force_reset_by_reinvoke 0
set tcl_relaxed_literal 0
set probe_exclude_patterns {}
set probe_packed_limit 4k
set probe_unpacked_limit 16k
set assert_internal_msg no
set svseed 1
set assert_reporting_mode 0
set vcd_compact_mode 0
alias . run
alias quit exit
database -open -shm -into waves.shm waves -default
probe -create -database waves tb.RGB0 tb.RGB1 tb.btn tb.clk tb.led tb.sclk_d1 tb.sclk_d2 tb.sclk_fall_edge tb.sclk_rise_edge tb.slave_bit_count tb.slave_cs_active tb.slave_cs_asserted tb.slave_cs_d1 tb.slave_mem tb.slave_shift_reg tb.spi_cs_n_out tb.spi_miso_in tb.spi_mosi_out tb.spi_sclk_out tb.sw tb.tb_slave_addr tb.tb_slave_data tb.tb_slave_is_read tb.tb_slave_is_write

simvision -input /cad/data/ameghana21/master_lokesh/syn/sim/.simvision/1752814_ameghana21_sscd48.iitk.ac.in_autosave.tcl.svcf

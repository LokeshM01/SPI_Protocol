set_db information_level 4
set library {tcbn65gpluswc_ccs.lib}
set_db lib_search_path {/cad/TechLib/TSMC65/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/CCS/tcbn65gplus_200a}
set_db library $library
set BASEDIR "../presyn"
set OUTDIR "."
set VERILOG_IN1 $BASEDIR/slave.v
set VERILOG_OUT $OUTDIR/slave_syn.v
set SDF_OUT $OUTDIR/slave_syn.sdf
set SDC_OUT $OUTDIR/slave_syn.sdc
read_hdl -v2001 $VERILOG_IN1
elaborate 
set_units -capacitance 1.0pF -time 1.0ns 
set_db use_tiehilo_for_const unique 
set_operating_conditions -library tcbn65gpluswc_ccs WCCOM
set_wire_load_model -name G5K -library tcbn65gpluswc_ccs
create_clock -name clk -period 100 -waveform {0 50} [get_ports clk]
set_clock_latency -max 0.25 [get_clocks clk]
set_clock_uncertainty 15 [get_clocks clk]
report clocks
set_load 0.1 [all_outputs]  
set_max_capacitance 0.1 [all_inputs]
get_db [get_designs slave] .tns
# set_max_fanout 20 [get_designs slave]
set_max_transition 0.6 [get_designs slave]
syn_gen
syn_map
syn_opt -incr
report timing
write_sdf -version "OVI 2.1" -design slave -precision 4 -edges check_edge -setuphold merge_when_paired -recrem split -nonegchecks > $SDF_OUT
write_sdc > $SDC_OUT
write_hdl > $VERILOG_OUT
write_db  -to_file slave_syn.db
# power analysis
read_netlist slave_syn.v
current_design slave
read_vcd sim/tb.vcd -vcd_scope tb.u_dut
report power > rcreport.log


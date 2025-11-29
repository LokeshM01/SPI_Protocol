# =============================================================
# Pure Cadence Genus minimal synthesis script
# Converted from RC-style script — minimal defaults chosen
# =============================================================

# -------------------------
# User-editable variables
# -------------------------
set BASEDIR "../presyn"
set OUTDIR "."
set VERILOG_TOP "$BASEDIR/slave_top.v"

set VERILOG_OUT "$OUTDIR/slave_syn.v"
set SDF_OUT     "$OUTDIR/slave_syn.sdf"
set SDC_OUT     "$OUTDIR/slave_syn.sdc"

# -------------------------
# Library / search path
# -------------------------
# set your library filename (name Genus will resolve via search path)
set DB_LIBRARY "tcbn65gpluswc_ccs.lib"
set_db init_lib_search_path  {/cad/TechLib/TSMC65/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/CCS/tcbn65gplus_200a}
set_db library $DB_LIBRARY

# -------------------------
# Basic verbosity / env
# -------------------------
# Keep Genus UI defaults (common_ui true). This script uses Genus-native commands.
set_db information_level 4

# -------------------------
# Read & elaborate
# -------------------------
read_hdl -v2001 $VERILOG_TOP
elaborate

# Optional sanity checks
check_design > $OUTDIR/reports/check_design_elab.log

# -------------------------
# Operating conditions
# -------------------------
# Minimal: use library default operating condition name if required.
# If you have a specific operating condition object, set it here. For minimal run we rely on default.
# Example (uncomment and edit if you have explicit OCs):
# set_db operating_conditions {WCCOM}

# -------------------------
# Clock (minimal)
# -------------------------
# Using 20 ns period and 50% duty (waveform 0->10). Adjust if needed.
create_clock -name clk -period 20 -waveform {0 10} [get_ports clk]

# set a small clock uncertainty if desired (optional). Minimal: keep as tool default.
# set_clock_uncertainty 0.10 clk

# -------------------------
# Simple global constraints (kept minimal)
# -------------------------
# Limits (units: ns for transition, unitless for fanout)
set_max_transition 0.6 /designs/slave_top
set_max_fanout 100 /designs/slave_top

# If you want to keep loads/transitions on I/O later, add set_load / set_input_delay / set_output_delay

# -------------------------
# Pre-synthesis reports (optional but useful)
# -------------------------
report clocks -generated
report clocks -ideal
report timing -lint -verbose > $OUTDIR/reports/presyn_timing

# -------------------------
# Set the top design (Genus requires this)
# -------------------------
set_db design_top slave_top

# -------------------------
# Synthesis flow (pure Genus syntax)
# -------------------------
syn_generic       ;# RTL → generic
syn_map           ;# generic → technology cells
syn_opt -incr     ;# incremental timing/area/power optimization


# Optional: clock gating reports (kept since you used it previously)
report_clock_gating -detail

# -------------------------
# Post-synthesis reports
# -------------------------
report timing > $OUTDIR/reports/postsyn_timing
report_design_rules > $OUTDIR/reports/design_rules.txt
report_power -depth 5 > $OUTDIR/reports/power_report_activity20percent.log

# -------------------------
# Output files
# -------------------------
# Genus write commands (pure Genus-style)
write_sdf -top slave_top -file $SDF_OUT -precision 5
write_sdc -file $SDC_OUT
write_verilog -output $VERILOG_OUT

# Save Genus DB if you want to re-open later
write_db -to_file slave_syn.db

# -------------------------
# End of script
# -------------------------
puts "Genus synthesis script completed (minimal). Outputs:"
puts "  RTL out:   $VERILOG_OUT"
puts "  SDF out:   $SDF_OUT"
puts "  SDC out:   $SDC_OUT"
puts "  DB saved:  slave_syn.db"


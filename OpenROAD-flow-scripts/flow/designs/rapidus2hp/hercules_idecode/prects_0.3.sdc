source $::env(PLATFORM_DIR)/util.tcl

#set sdc_version 2.1
set sdc_version 1.4
current_design hercules_idecode

set clk_period 370
# Roughly 150ps for a 370ps clock
set input_pct 0.4054
# Roughly 50ps for a 370ps clock
set output_pct 0.1351

convert_time_value clk_period

set_max_fanout 32 [current_design]
set_load [convert_cap_value 10] [all_outputs]
set_max_capacitance [convert_cap_value 10] [all_inputs]

create_clock -name "clk" -add -period $clk_period \
  -waveform [list 0.0 [expr { 0.5 * $clk_period }]] [get_ports clk]

set_clock_latency $clk_period clk

### Setup input delay is set to 20% of CT
set_input_delay [expr { $clk_period * $input_pct }] -clock clk [all_inputs]
set_output_delay [expr { $clk_period * $output_pct }] -clock clk [all_outputs]

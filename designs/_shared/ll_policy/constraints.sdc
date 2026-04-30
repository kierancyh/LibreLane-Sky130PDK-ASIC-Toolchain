# Shared LibreLane/OpenLane timing constraints for FINAL_ALU

create_clock -name clk -period $::env(CLOCK_PERIOD) [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]

# Do not time the clock as a data input.
set_false_path -from [get_ports clk]

# Minimal electrical guidance for the resizer/signoff flow.
set_load 0.020 [all_outputs]
set_max_transition 1.50 [current_design]
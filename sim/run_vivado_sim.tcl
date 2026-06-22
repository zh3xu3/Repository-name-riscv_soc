# Vivado Simulation Script for RISC-V SoC
# Usage: vivado -mode batch -source run_vivado_sim.tcl

# Create project
create_project -in_memory -part xc7a35tcpg236-1

# Add source files
add_files [glob ../rtl/core/*.v]
add_files [glob ../rtl/mem/*.v]
add_files [glob ../rtl/periph/*.v]
add_files ../rtl/soc_top.v
add_files tb_soc.v

# Set top module
set_property top tb_soc [current_fileset]

# Run simulation
launch_simulation -mode behavioral

# Run for sufficient time
run 100us

# Check results
puts "========================================="
puts "Simulation Complete"
puts "========================================="

# Close project
close_project

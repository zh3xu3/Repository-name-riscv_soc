# RISC-V SoC Full Simulation Script
# This script runs the complete testbench with all 22 tests

puts "========================================="
puts "RISC-V SoC Simulation"
puts "========================================="

# Create project in current directory
create_project -force sim_proj sim_proj -part xc7a35tcpg236-1

# Add all source files
set rtl_dir "../rtl"
add_files [glob $rtl_dir/core/*.v]
add_files [glob $rtl_dir/mem/*.v]
add_files [glob $rtl_dir/periph/*.v]
add_files $rtl_dir/soc_top.v

# Add testbench
add_files -fileset sim_1 tb_soc.v

# Set top module for simulation
set_property top tb_soc [current_fileset -simset]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Compiling design..."

# Launch simulation
launch_simulation -mode behavioral

puts "Running simulation..."
puts "Expected: 22 PASS, 0 FAIL"

# Run simulation for sufficient time
run 200us

# Check results
puts "========================================="
puts "Simulation Complete"
puts "========================================="

# Close simulation
close_sim

puts "Done!"

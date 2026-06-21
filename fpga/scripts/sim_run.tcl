# Vivado Simulation Run Script
# Usage: vivado -mode batch -source sim_run.tcl

set project_dir "../vivado_project"
set project_name "riscv_soc"
set project_path "${project_dir}/${project_name}.xpr"

# Open project
if {![file exists ${project_path}]} {
  puts "ERROR: Project not found at ${project_path}"
  exit 1
}
open_project ${project_path}

# Copy hex file to sim directory
set hex_file "../../inst_mem.hex"
set sim_dir "${project_dir}/${project_name}.sim/sim_1/behav/xsim"
file mkdir ${sim_dir}
file copy -force ${hex_file} ${sim_dir}/

# Set simulation runtime to 5ms
set_property -name {xsim.simulate.runtime} -value {5ms} -objects [get_filesets sim_1]

# Launch behavioral simulation
puts "========================================="
puts " Launching Behavioral Simulation (5ms)"
puts "========================================="

launch_simulation -simset sim_1 -mode behavioral

# Run simulation
run 5ms

# Print test results from simulation log
puts ""
puts "========================================="
puts " Simulation Complete"
puts "========================================="

# Close simulation
close_sim

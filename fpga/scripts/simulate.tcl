# Vivado Behavioral Simulation Script
# Usage: vivado -mode batch -source simulate.tcl

set project_name "riscv_soc"
set project_dir  "../vivado_project"

# Check project
if {![file exists ${project_dir}/${project_name}.xpr]} {
  puts "ERROR: Project not found. Run create_project.tcl first."
  exit 1
}

open_project ${project_dir}/${project_name}.xpr

puts "========================================="
puts " Running Behavioral Simulation"
puts "========================================="

# Ensure hex file is in simulation directory
set hex_file "../../inst_mem.hex"
set sim_dir ${project_dir}/${project_name}.sim/sim_1/behav
file mkdir ${sim_dir}
file copy -force ${hex_file} ${sim_dir}/

# Launch simulation
set_property -name {xsim.simulate.runtime} -value {5ms} -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral

puts "========================================="
puts " Simulation Complete"
puts "========================================="

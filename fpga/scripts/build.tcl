# Automated Build Script for RISC-V SoC
# Usage: vivado -mode batch -source build.tcl

# ================================================================
# Configuration
# ================================================================
set project_name "riscv_soc"
set project_dir  "../vivado_project"

# Check if project exists
if {![file exists ${project_dir}/${project_name}.xpr]} {
  puts "ERROR: Project not found. Run create_project.tcl first."
  exit 1
}

# Open project
open_project ${project_dir}/${project_name}.xpr

puts "========================================="
puts " Starting Build: ${project_name}"
puts "========================================="

# ================================================================
# Synthesis
# ================================================================
puts "\n>>> Running Synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
  puts "ERROR: Synthesis failed!"
  exit 1
}
puts ">>> Synthesis complete."

# ================================================================
# Implementation
# ================================================================
puts "\n>>> Running Implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
  puts "ERROR: Implementation failed!"
  exit 1
}
puts ">>> Implementation complete."

# ================================================================
# Reports
# ================================================================
puts "\n>>> Generating Reports..."

# Utilization Report
open_run impl_1
report_utilization -file ${project_dir}/utilization.rpt
report_timing_summary -file ${project_dir}/timing.rpt

puts ">>> Reports saved to ${project_dir}/"

# ================================================================
# Summary
# ================================================================
set bitstream [glob -nocomplain ${project_dir}/${project_name}.runs/impl_1/*.bit]
if {$bitstream != ""} {
  puts "\n========================================="
  puts " BUILD SUCCESSFUL"
  puts " Bitstream: $bitstream"
  puts "========================================="
} else {
  puts "\nERROR: Bitstream not found!"
  exit 1
}

close_project

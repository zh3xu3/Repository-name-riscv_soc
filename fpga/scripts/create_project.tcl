# Vivado TCL Script for RISC-V SoC Project
# Usage: vivado -mode batch -source create_project.tcl
# Or in Vivado TCL console: source create_project.tcl

# ================================================================
# Configuration
# ================================================================
set project_name "riscv_soc"
set project_dir  "../vivado_project"
set part         "xc7a35tfgg484-2"
set top_module   "fpga_top"

# Source paths (relative to this script's location)
set rtl_dir      "../../rtl"
set fpga_dir     ".."
set hex_file     "../../inst_mem.hex"
set tb_file      "../../sim/tb_soc.v"

# ================================================================
# Create Project
# ================================================================
create_project ${project_name} ${project_dir} -part ${part} -force
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# ================================================================
# Add RTL Sources
# ================================================================
# Core
add_files -norecurse [glob ${rtl_dir}/core/*.v]

# Memory
add_files -norecurse [glob ${rtl_dir}/mem/*.v]

# Peripherals
add_files -norecurse [glob ${rtl_dir}/periph/*.v]

# SoC top
add_files -norecurse ${rtl_dir}/soc_top.v

# FPGA top
add_files -norecurse ${fpga_dir}/fpga_top.v

# ================================================================
# Add Memory Initialization File
# ================================================================
add_files -norecurse ${hex_file}
set_property file_type {Memory Initialization Files} [get_files inst_mem.hex]
set_property library xil_defaultlib [get_files inst_mem.hex]

# ================================================================
# Add Constraints
# ================================================================
add_files -norecurse -fileset constrs_1 ${fpga_dir}/constraints/a7_lite.xdc

# ================================================================
# Set Top Module (Synthesis)
# ================================================================
set_property top ${top_module} [current_fileset]

# ================================================================
# Simulation Setup
# ================================================================
# Create simulation fileset if it doesn't exist
if {[llength [get_filesets -quiet sim_1]] == 0} {
  create_fileset -simset sim_1
}

# Add testbench to simulation
add_files -norecurse -fileset sim_1 ${tb_file}
set_property top tb_soc [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Copy hex file to simulation directory for $readmemh
set sim_dir ${project_dir}/${project_name}.sim/sim_1/behav
file mkdir ${sim_dir}
file copy -force ${hex_file} ${sim_dir}/

# Set simulation runtime
set_property -name {xsim.simulate.runtime} -value {5ms} -objects [get_filesets sim_1]

# ================================================================
# Synthesis Strategy
# ================================================================
set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

# ================================================================
# Implementation Strategy
# ================================================================
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

# ================================================================
# Summary
# ================================================================
puts ""
puts "========================================="
puts " RISC-V SoC Vivado Project Created"
puts "========================================="
puts " Part:       ${part}"
puts " Top:        ${top_module}"
puts " Project:    ${project_dir}/${project_name}"
puts "========================================="
puts ""
puts "Build commands:"
puts "  launch_runs synth_1 -jobs 4"
puts "  wait_on_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
puts ""
puts "Simulate:"
puts "  launch_simulation -simset sim_1 -mode behavioral"

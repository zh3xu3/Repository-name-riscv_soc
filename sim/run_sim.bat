@echo off
echo ========================================
echo RISC-V SoC Vivado Simulation
echo ========================================

REM Generate test program
echo Generating test program...
cd ..\tests\sw
python gen_uart_gpio.py
copy inst_mem.hex ..\..\sim\
cd ..\..\sim

REM Run Vivado simulation
echo Running Vivado simulation...
vivado -mode batch -source run_vivado_sim.tcl

echo.
echo Simulation complete!
pause

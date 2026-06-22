@echo off
echo ========================================
echo RISC-V SoC Vivado Simulation
echo ========================================

set VIVADO=D:\fpga\2025.2\Vivado\bin
set SIM_DIR=%~dp0
set RTL_DIR=%~dp0..\rtl

cd /d "%SIM_DIR%"

echo.
echo Step 1: Generating test program...
cd ..\tests\sw
python gen_uart_gpio.py
copy inst_mem.hex ..\..\sim\
cd ..\..\sim

echo.
echo Step 2: Compiling with xvlog...
"%VIVADO%\xvlog.bat" -log compile.log ^
    "%RTL_DIR%\core\alu.v" ^
    "%RTL_DIR%\core\branch_comp.v" ^
    "%RTL_DIR%\core\branch_pred.v" ^
    "%RTL_DIR%\core\control.v" ^
    "%RTL_DIR%\core\csr.v" ^
    "%RTL_DIR%\core\divider.v" ^
    "%RTL_DIR%\core\imm_gen.v" ^
    "%RTL_DIR%\core\reg_file.v" ^
    "%RTL_DIR%\core\riscv_core.v" ^
    "%RTL_DIR%\mem\data_mem.v" ^
    "%RTL_DIR%\mem\icache.v" ^
    "%RTL_DIR%\mem\inst_mem.v" ^
    "%RTL_DIR%\periph\dma.v" ^
    "%RTL_DIR%\periph\gpio.v" ^
    "%RTL_DIR%\periph\i2c.v" ^
    "%RTL_DIR%\periph\plic.v" ^
    "%RTL_DIR%\periph\pwm.v" ^
    "%RTL_DIR%\periph\spi.v" ^
    "%RTL_DIR%\periph\uart.v" ^
    "%RTL_DIR%\periph\uart_rx.v" ^
    "%RTL_DIR%\periph\uart_tx.v" ^
    "%RTL_DIR%\periph\wdt.v" ^
    "%RTL_DIR%\soc_top.v" ^
    tb_soc.v

if errorlevel 1 (
    echo.
    echo ERROR: Compilation failed!
    pause
    exit /b 1
)

echo.
echo Step 3: Elaborating design...
"%VIVADO%\xelab.bat" -log elaborate.log -debug all tb_soc -s sim_snapshot

if errorlevel 1 (
    echo.
    echo ERROR: Elaboration failed!
    pause
    exit /b 1
)

echo.
echo Step 4: Running simulation...
"%VIVADO%\xsim.bat" sim_snapshot -log simulate.log -runall

echo.
echo ========================================
echo Simulation Complete!
echo ========================================
pause

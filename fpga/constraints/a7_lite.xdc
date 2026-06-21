# A7_lite Board Constraints (Artix-7 XC7A35T)
# Adapted from official A7_lite.xdc

# ================================================================
# Clock
# ================================================================
set_property PACKAGE_PIN J19 [get_ports clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m]
create_clock -period 20.000 -name clk_50m -waveform {0.000 10.000} [get_ports clk_50m]

# ================================================================
# Reset (active-low)
# ================================================================
set_property PACKAGE_PIN L18 [get_ports rst_n_in]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n_in]
set_property PULLUP TRUE [get_ports rst_n_in]

# ================================================================
# UART
# ================================================================
set_property PACKAGE_PIN V2 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN U2 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PULLUP TRUE [get_ports uart_rx]

# ================================================================
# LEDs
# ================================================================
set_property PACKAGE_PIN M18 [get_ports led1]
set_property IOSTANDARD LVCMOS33 [get_ports led1]

set_property PACKAGE_PIN N18 [get_ports led2]
set_property IOSTANDARD LVCMOS33 [get_ports led2]

# ================================================================
# SPI (directly on expansion header)
# ================================================================
set_property PACKAGE_PIN K17 [get_ports spi_sck]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sck]

set_property PACKAGE_PIN L17 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi]

set_property PACKAGE_PIN J17 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso]
set_property PULLUP TRUE [get_ports spi_miso]

set_property PACKAGE_PIN K18 [get_ports spi_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports spi_cs_n]

# ================================================================
# PWM outputs
# ================================================================
set_property PACKAGE_PIN V5 [get_ports pwm0]
set_property IOSTANDARD LVCMOS33 [get_ports pwm0]

set_property PACKAGE_PIN U5 [get_ports pwm1]
set_property IOSTANDARD LVCMOS33 [get_ports pwm1]

# ================================================================
# Configuration
# ================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ================================================================
# Bitstream Compression
# ================================================================
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# ================================================================
# PLL Generated Clock (auto-created by Vivado, explicit for clarity)
# ================================================================
# PLL: 50MHz in → 100MHz out (CLKFBOUT_MULT=20, CLKOUT0_DIVIDE=10)
# Vivado auto-creates this from PLL_BASE, but we add it for safety
create_generated_clock -name clk_100m -source [get_ports clk_50m] \
  -multiply_by 2 [get_pins u_pll/CLKOUT0]

# ================================================================
# Reset Synchronizer - false path on async reset
# ================================================================
set_false_path -from [get_ports rst_n_in] -to [get_pins rst_sync[0]/D]

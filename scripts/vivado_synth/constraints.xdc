# Minimal constraint set for picorv32_ecc_top synthesis/timing exploration.
# This module has no physical board I/O (UART, LEDs, switches) — every port
# is either clk/resetn, a status output, or a simulation-only fault-injection
# input. Only the clock is constrained; all other ports are left unconstrained
# for this synthesis-and-timing-report run (not a bitstream-for-hardware flow).

create_clock -period 10.000 -name clk [get_ports clk]

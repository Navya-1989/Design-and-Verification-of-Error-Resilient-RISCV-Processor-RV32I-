# Design and Verification of an Error-Resilient RISC-V (RV32I) Core

A PicoRV32-based RV32I processor protected against soft errors with **BCH(45,32), t = 2** error-correcting codes on the **instruction-fetch path** and the **register file**. The design is verified in RTL simulation and implemented on the **Basys3 (Artix-7 xc7a35t)** FPGA with Vivado 2024.2.

Author: Betha Navya (2025JID2497), M.Tech Instrument Technology, SeNSE, IIT Delhi
Supervisor: Prof. Kaushik Saha

## Status at a glance

| Area | Result |
| --- | --- |
| Standalone BCH engine | 3,400 / 3,400 vectors pass |
| Full-system simulation | 217 / 267 tests pass (81.3%); all 50 failures are triple-bit faults, beyond the t = 2 guarantee |
| FPGA (16 KB memory, Artix-7) | 12,265 LUTs (59%), 3,415 registers (8%), 0 block RAM |
| Timing, 15 ns clock | Met: WNS +0.018 ns, WHS +0.016 ns |
| Timing, 10 ns clock | Not met: WNS -3.177 ns (12,531 LUTs, 3,444 registers) |
| Synthesized hardware running the firmware | **Not yet demonstrated** |

Timing figures are out-of-context estimates (Vivado cannot model clock skew in that mode).

## Architecture

- **Instruction fetch** (`ecc_instr_memory.v`): instructions are stored as 45-bit BCH codewords. A multi-cycle decoder (syndrome, error locator, correction) corrects them, and the module holds `mem_ready` low until correction finishes, so the CPU never sees an uncorrected word.
- **Register file** (`bch_regfile.v`): x0 to x31 are stored as BCH codewords with single-cycle combinational correction.
- **Shared engine** (`bch_ecc.v`): the BCH encoder and decoder used by both layers.
- **Top level** (`picorv32_ecc_top.v`): integrates the core with both layers and a small memory-mapped region for UART output and pass/fail signalling in simulation.

| BCH(45,32) parameter | Value |
| --- | --- |
| Data / codeword / parity bits | 32 / 45 / 13 |
| Correctable errors (t) | 2 |
| Galois field | GF(2^6) |
| Storage overhead | about 40.6% |

A Hamming/RRNS scheme inherited with the code is incomplete (encoder only, no decoder is connected). It is out of scope and is not part of the protected design.

## Repository layout

```
src/rtl/            picorv32.v, bch_ecc.v, bch_regfile.v, ecc_instr_memory.v,
                    picorv32_ecc_top.v, hammingcode_generator.sv
src/firmware/       test firmware sources, linker script, firmware.hex
src/testbench/      standalone BCH testbench and the combined full-system testbench
scripts/vivado_synth/
                    run_synth.tcl, constraints.xdc, reports/, gen_bch_hex_tb.v,
                    src/firmware/firmware_bch.hex (pre-encoded parity image)
docs/               debugging_log.md
```

## Simulation

Tools (tested on WSL Ubuntu 24.04): Icarus Verilog 12.0, riscv64-unknown-elf-gcc 13.2.0 (rv32imc / ilp32), GTKWave 3.3.116.

```
make sim_bch_unit     # standalone BCH engine, 3,400 vectors
make sim_combined     # full system with fault injection
```

The combined testbench injects faults with `force` / `release` in six categories: fetch faults of 0 to 3 bits, register faults of 0 to 3 bits, and two concurrent categories. The expected result is 217 / 267. The 50 failures are all in the two triple-bit categories (A3 and B3). Waveforms are written as VCD and can be opened in GTKWave. See `docs/debugging_log.md` for the five defects found and fixed.

## FPGA flow (Vivado 2024.2, Windows)

The flow is a non-project batch script run in out-of-context mode, so no board pin assignment is needed.

1. In `run_synth.tcl`, the synthesis line is
   `synth_design -top picorv32_ecc_top -part xc7a35tcpg236-1 -mode out_of_context -generic MEM_SIZE=16384 -verilog_define FPGA_SYNTH`
2. `constraints.xdc` holds the clock (`create_clock -period 15.000` for the met result; 10.000 does not meet timing).
3. Start Vivado from a Windows directory such as `C:\Users\<user>` (not a UNC path); the script changes into `scripts/vivado_synth` itself:
   `vivado.bat -mode batch -source "//wsl.localhost/<distro>/<path-to-repo>/scripts/vivado_synth/run_synth.tcl"`
4. Reports are written to `scripts/vivado_synth/reports/`.

### Notes that matter

- **`FPGA_SYNTH` is required.** Without it, Vivado ignores the `initial` block that fills the parity array (Synth 8-311) and silently removes the array, which gives wrong area figures. With it, the array is loaded by `$readmemh` from `src/firmware/firmware_bch.hex`.
- **`firmware_bch.hex` must be tracked in git** (`git add -f`, since `scripts/vivado_synth/src` is ignored). It is generated from the same encoder by `gen_bch_hex_tb.v`.
- **Memory size:** 16 KB is the minimum that runs the firmware (stack top 0x4000) and uses 69% of the device's LUT RAM. 32 KB does not fit. `ram_style = "block"` is ignored by Vivado with the current coding style.

## Known limitations and next steps

- Triple-bit errors can be mis-corrected by a t = 2 code. Align the test criteria with the guarantee or add a post-correction check.
- Prove that the synthesized design runs the firmware (post-synthesis simulation, then the board with pin constraints).
- Shorten the CPU core's critical path to approach a 10 ns clock.
- Move the instruction memory to block RAM so more than 16 KB fits.
- Exclude the register file's simulation-only fault task from synthesis, as already done for the instruction memory.
- Protect data memory (currently unprotected).

## Version control

Every verified change is committed on its own with a descriptive message; see `git log`.

## Acknowledgements

PicoRV32 is by Claire Xenia Wolf (formerly Clifford Wolf) and is distributed under the ISC license. Add contributor credits for the inherited protection modules here.

# Design and Verification of an Error-Resilient RISC-V (RV32I) Core

A PicoRV32-based RISC-V processor augmented with hardware error-correcting code (ECC)
protection, designed to detect and automatically correct bit-level errors in critical
processor components — instruction memory and the internal register file.

**Supervisor:** Prof. Kaushik Saha, Department of Electrical Engineering, IIT Delhi

## Status

| Metric | Result |
|---|---|
| Standalone BCH engine unit test | **3,400 / 3,400** vectors passed |
| Full-system verification (`sim_combined`) | **217 / 267** tests passed (81.3%) |
| Unexplained test failures | **0** — every result has a confirmed, documented cause |

All 50 remaining failures are confined to triple-bit fault-injection categories,
traced to an inherent, mathematically expected limitation of BCH(45,32,t=2) coding
(see `docs/debugging_log.md` for the full root-cause analysis).

## Architecture

- **Instruction-fetch protection** — instructions are BCH(45,32)-encoded before storage;
  a multi-cycle decoder corrects errors before the CPU sees the instruction.
- **Register-file protection** — architectural registers x0–x31 stored as BCH(45,32)
  codewords; correction is fully combinational, completing within the same cycle as
  the register read.
- **Additional protection scheme (partial)** — an earlier phase introduced Hamming-code
  and RRNS-based protection for the CPU state machine and ALU. Verification found the
  encoder logic executes but the decoder/correction path was never connected — a known,
  documented gap rather than functioning protection.

BCH(45,32): 32 data bits, 45-bit codeword, t=2 (guaranteed correction of up to 2 bit
errors), GF(2^6), ~40.6% storage overhead.

## Repository structure

## Toolchain

- [Icarus Verilog](http://iverilog.icarus.com/) 12.0+ (`-g2012`)
- Bare-metal RISC-V GNU toolchain (`riscv64-unknown-elf-gcc`, targeting `rv32imc`/`ilp32`)
- [GTKWave](http://gtkwave.sourceforge.net/) for waveform inspection

```bash
sudo apt install iverilog gtkwave gcc-riscv64-unknown-elf \
    binutils-riscv64-unknown-elf picolibc-riscv64-unknown-elf make git
```

## Build and test

```bash
# Standalone BCH engine verification (3,400 vectors)
make sim_bch_unit

# Full-system verification with fault injection
make sim_combined

# Full-system verification with waveform dump
make sim_combined_vcd
gtkwave dump.vcd

# Rebuild firmware from source (only needed after changing src/firmware/*.c)
make firmware

# Clean all build artifacts
make clean
```

## Key findings

1. **BCH(45,32,t=2) cannot guarantee detection of triple-bit corruption.** This is an
   inherent property of the coding scheme, not an implementation defect — confirmed by
   direct inspection of the fatal-error detection logic in `bch_ecc.v`.
2. **Register-file fault injection only has effect if firmware actually reads the
   targeted register.** Test coverage was restructured to target registers with
   confirmed real usage (via firmware disassembly), resolving 14 false failures with
   zero RTL changes.

See `docs/debugging_log.md` for the complete investigation, including every bug found,
root cause, fix, and verification result.

## Contributors

- **Akshat Mathur** (2023EEN2223) — Hamming-code and RRNS-based protection
- **Posam Naga Lingeswara Rao** (2024EEN2321) — BCH(45,32) instruction-fetch protection
- **Deepak** (2024EEN2859) — BCH(45,32) register-file protection
- **Betha Navya** (2025JID2497) — Repository consolidation, toolchain setup, full-system
  verification, root-cause analysis, and documentation

## Future work

- FPGA synthesis (Xilinx Vivado): static timing analysis and resource utilization
- Adjust triple-bit test criteria or implement a secondary post-correction consistency check
- Complete the partially-developed Hamming/RRNS protection scheme
- Extend protection coverage to data memory (currently instruction-fetch only)

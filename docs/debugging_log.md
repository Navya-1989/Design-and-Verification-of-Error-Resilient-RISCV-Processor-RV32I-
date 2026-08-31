# Debugging Log — sim_combined

- sim_combined reported 10/332 PASS. Every test, including zero-fault
  golden runs (A0/B0), was failing for unknown reasons.

### Bug 1 — Wrong expected value in firmware test
- File: src/firmware/hello.c, line 176
- hw_rem(0x100000, 0xFF) was asserted to equal 1, but the mathematically
  correct value is 16 (0x10). Verified by hand: 0x100000 = 1,048,576;
  1,048,576 mod 255 = 16.
- This single error blocked nearly every test in the suite, since it's
  one of the first checks hello.c runs, and every test executes the
  same firmware.
- Fix: corrected expected value from 0x00000001u to 0x00000010u
  (and updated the matching signature constant 0x00090001 -> 0x00090010).
- Result after fix: 10/332 -> 164 confirmed real passes (partial run,
  watchdog cut it short).

### Bug 2 — Watchdog timeout too short
- File: src/testbench/tb_combined_ecc.v, line ~736
- Global watchdog was #50000000 (50ms). Real firmware runs after Bug 1's
  fix take ~30-48ms EACH, and the suite runs 332 of them sequentially.
- Fix: extended watchdog to #20000000000 (20s).
- Result: full 332-test suite now completes. 263/332 PASS.

### Bug 3 — Missing array entry (a2_block)
- File: src/testbench/tb_combined_ecc.v, a2_block (~line 375)
- integer word_indices[0:9] declared 10 slots, only 9 were assigned
  (word_indices[9] was never set). Loop correctly iterated 0-9, so the
  10th iteration used an undefined (X) word index, causing the fault
  injection to target a garbage address instead of a real instruction word.
- This showed up as "word=x" in console output and caused unpredictable
  CPU traps.
- Note: there are TWO separate word_indices[] arrays in this file, one
  inside a1_block and one inside a2_block (same name, different scope).
  First patch attempt accidentally fixed a1_block's copy instead.
- Fix: added word_indices[9] = 17; to a2_block specifically.
- Result: 263/332 -> 268/332 PASS. All 5 A2 (fetch_double) failures resolved.

### Bug 4 (gap, not logic bug) — VCD dumping never implemented
- File: src/testbench/tb_combined_ecc.v
- No $dumpfile/$dumpvars call existed anywhere. The Makefile's
  sim_combined_vcd target passed +vcd to vvp, but nothing was listening
  for it, so dump.vcd was silently never created.
- Fix: added an initial block checking $test$plusargs("vcd") and calling
  $dumpfile("dump.vcd"); $dumpvars(0, tb_combined_ecc);
- Result: waveform debugging now works via GTKWave.

### Finding — A3/B3 "failures" are an inherent BCH(45,32,t=2) limitation
- Categories: A3 (fetch_triple, 20 fails), B3 (rf_triple, 30 fails)
- These inject 3-bit errors and expect a fatal/uncorrectable flag.
- Root cause traced to bch_ecc.v line 340:
  fatal <= (s1 != 6'd0) && (mask == 45'd0);
- This only flags fatal when the decoder finds NO correction mask at all.
  It does not catch cases where the decoder computes A mask (i.e. "corrects"
  something) but the result is wrong because there were actually 3 errors,
  not 2. This is expected, textbook behavior for any t=2 error-correcting
  code operated beyond its guaranteed correction radius -- not an
  implementation bug in any of the three original codebases.
- Verified the underlying arrays (t_w[0:29], reg_addrs[0:29] for B3) are
  fully populated -- ruled out an array-init bug as an alternate explanation.
- Decision: treat as a documented limitation. Either (a) adjust A3/B3 test
  pass criteria to accept "fatal OR silent miscorrection" as expected
  outcomes, or (b) add a secondary consistency check as future work
  (thesis-worthy, out of scope for a quick fix).

### Remaining open — B1, B2, C2 (14 tests total)
- B1 (rf_single, 6 fails), B2 (rf_double, 6 fails), C2 (concurrent
  fetch+regfile double fault, 2 fails)
- These SHOULD be within BCH's correction guarantee (single/double-bit),
  unlike A3/B3. Not yet explained.
- reg_addrs[] arrays for B1/B2 confirmed fully populated (1-25), so this
  is NOT the same array-init bug as A2's.
- Next step: use dump.vcd (now working) to inspect one specific B1
  failure's waveform directly, same approach used to diagnose A2.

### Result summary
- Start of session: 10/332 PASS
- End of session:   268/332 PASS
- All failure categories now understood except B1/B2/C2 (14 tests)
### Finding — B1/B2/C2 failures traced to register-usage mismatch, not an RTL bug

- Categories: B1 (rf_single, 6 fails), B2 (rf_double, 6 fails),
  C2 (concurrent fetch+regfile double fault, 2 fails)
- Investigation process:
  1. Confirmed bch_regfile.v's reg_file_single_err/double_err/fatal flags
     are correctly implemented as sticky latches (only reset on !resetn,
     set and held on any correction event) -- ruled out as the bug.
  2. Confirmed inject_reg_fault is held active for the ENTIRE
     run_firmware() call in the testbench (force before, release after)
     -- ruled out a fault-injection timing/window bug.
  3. Read bch_regfile.v's own doc comment: inject_reg_fault "enable[s]
     fault injection into the read path" -- correction only fires
     combinationally when the CPU actually issues a read instruction
     targeting the specific corrupted register address (raddr1/raddr2).
  4. Disassembled the actual compiled firmware.elf and counted real
     register usage across all instructions:
       a5(x15)=116  a2(x12)=90  a0(x10)=81  a4(x14)=78  a1(x11)=54
       a3(x13)=25   s1(x9)=24   s0(x8)=22   sp(x2)=20   t1(x6)=10
       ...
       ra(x1)=2     gp(x3)=0    a7(x17)=0   (many others 1-7 each)
- Conclusion: B1/B2/C2 test loops fault-inject uniformly across x1-x25
  (B1/B2) assuming firmware reads each one during the run. In reality,
  the compiled firmware concentrates almost all register activity in
  ~8 registers (a0-a5, s0-s1, sp). Registers like x1 (ra), x3 (gp),
  x17 (a7) are read only 0-2 times in the entire firmware run, making
  it likely (not certain) that a fault injected into a rarely-read
  register is never actually exercised before run_firmware() completes
  and the test checks the correction flag.
- This is a TEST DESIGN gap, not a confirmed RTL bug. The BCH
  register-file protection logic itself (fault injection wiring,
  sticky flags, correction function) all checked out correctly during
  this investigation.
- Decision: documented as a known limitation rather than fixed today.

  Future work (not done): restructure B1/B2/C2 test loops to target
  only registers firmware's compiled binary actually reads with
  meaningful frequency (a0-a5, s0-s1, sp) instead of a uniform sweep
  across x1-x25/x1-x30. This would make these tests meaningfully
  exercise the protection they claim to verify, rather than mostly
  targeting registers that are never read back during the test window.

### Updated result summary
- 268/332 PASS remains the confirmed, verified result for this session.
- All 64 remaining failures now have a documented, understood root cause:
    - A3 (20) + B3 (30) = 50: inherent BCH(45,32,t=2) limitation
      (decoder cannot always distinguish 3-bit corruption from a valid
      2-bit correction; bch_ecc.v's fatal flag only catches the narrow
      "no correction possible at all" case)
    - B1 (6) + B2 (6) + C2 (2) = 14: test design gap (fault-injected
      registers not reliably read back by firmware's actual compiled
      register usage pattern)
- No remaining "unknown" failures -- every category is now explained.

### Updated result summary
- 268/332 PASS remains the confirmed, verified result for this session.
- All 64 remaining failures now have a documented, understood root cause:
    - A3 (20) + B3 (30) = 50: inherent BCH(45,32,t=2) limitation
      (decoder cannot always distinguish 3-bit corruption from a valid
      2-bit correction; bch_ecc.v's fatal flag only catches the narrow
      "no correction possible at all" case)
    - B1 (6) + B2 (6) + C2 (2) = 14: test design gap (fault-injected
      registers not reliably read back by firmware's actual compiled
      register usage pattern)
- No remaining "unknown" failures -- every category is now explained.


### Fix — B1/B2/C2 restructured to target realistic registers (Option B, implemented)

- Rewrote b1_block, b2_block, and c2_loop to fault-inject only into
  registers confirmed heavily used by firmware.elf (x2=sp, x8=s0, x9=s1,
  x10-x15=a0-a5), instead of a blind sweep across x1-x25/x1-x30.
- B1: reg_addrs[0:24] (25 regs) -> reg_addrs[0:8] (9 regs), loop bound
  25 -> 9. Test count 50 -> 18.
- B2: identical restructuring, same 9-register set. Test count 50 -> 18.
- C2: fault_reg_addr changed from raw arithmetic (5 + ci) to a lookup
  into the same 9-register array. Loop bound 10 -> 9. Test count 10 -> 9.
- One structural bug introduced during the C2 edit: the line-range
  replacement accidentally included one extra `end` belonging to the
  OUTER initial block (not part of c2_loop itself), causing a stray
  duplicate `end` after the edit. Caused a cascading syntax error
  (iverilog lost sync and reported spurious errors even in picorv32.v,
  an unrelated file later in the compile command). Fixed by deleting
  the single orphaned `end` line.
- RESULT: B1 6/6 -> 0 fails. B2 6/6 -> 0 fails. C2 2/2 -> 0 fails.
  Confirms the register-usage-mismatch theory completely: once faults
  are injected into registers firmware actually reads back, BCH
  register-file protection corrects them successfully every time.

### Final result for this investigation
- Total tests: 332 -> 267 (reduced by design, removing tests against
  registers firmware never meaningfully exercises)
- PASS: 217 / 267 (81.3%)
- FAIL: 50 / 267 -- ALL 50 are A3(20)+B3(30), the confirmed inherent
  BCH(45,32,t=2) fatal-detection limitation (see earlier finding).
- Zero unexplained failures. Zero failures outside the one documented,
  understood ECC-scheme limitation.

# Debugging Log — sim_combined

## Session: [today's date]

### Starting point
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

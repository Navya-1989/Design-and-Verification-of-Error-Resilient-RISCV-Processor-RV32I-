module tb_dump;
  ecc_instr_memory #(.MEM_SIZE(16384)) dut();
  initial begin
    #1;
    $writememh("scripts/vivado_synth/test/firmware_bch.hex", dut.instr_mem_bch);
    $finish;
  end
endmodule

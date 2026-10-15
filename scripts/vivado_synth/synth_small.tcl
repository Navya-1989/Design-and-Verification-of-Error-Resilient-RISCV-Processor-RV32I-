read_verilog -sv {
    ../../src/rtl/picorv32.v
    ../../src/rtl/hammingcode_generator.sv
    ../../src/rtl/bch_ecc.v
    ../../src/rtl/bch_regfile.v
    ../../src/rtl/ecc_instr_memory.v
    ../../src/rtl/picorv32_ecc_top.v
}
read_xdc ./constraints.xdc
synth_design -top picorv32_ecc_top -part xc7a35tcpg236-1 -mode out_of_context -generic MEM_SIZE=1024
file mkdir ./reports_small
report_utilization -hierarchical -file ./reports_small/util_hier_small.rpt

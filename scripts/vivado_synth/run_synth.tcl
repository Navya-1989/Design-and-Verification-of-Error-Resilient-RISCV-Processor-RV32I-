# =============================================================
# Non-project-mode synthesis + implementation for picorv32_ecc_top
# Target: Basys3 (Artix-7, xc7a35tcpg236-1)
# Run with: vivado -mode batch -source run_synth.tcl
# =============================================================

set part_name xc7a35tcpg236-1
set top_module picorv32_ecc_top
set report_dir ./reports
file mkdir $report_dir

read_verilog -sv {
    ../../src/rtl/picorv32.v
    ../../src/rtl/hammingcode_generator.sv
    ../../src/rtl/bch_ecc.v
    ../../src/rtl/bch_regfile.v
    ../../src/rtl/ecc_instr_memory.v
    ../../src/rtl/picorv32_ecc_top.v
}

read_xdc ./constraints.xdc

synth_design -top $top_module -part $part_name -generic MEM_SIZE=32768

write_checkpoint -force ${report_dir}/post_synth.dcp
report_utilization -file ${report_dir}/utilization_post_synth.rpt
report_timing_summary -file ${report_dir}/timing_post_synth.rpt

opt_design
place_design
route_design

write_checkpoint -force ${report_dir}/post_route.dcp
report_utilization -file ${report_dir}/utilization_post_route.rpt
report_timing_summary -file ${report_dir}/timing_post_route.rpt
report_timing -sort_by group -max_paths 10 -path_type summary -file ${report_dir}/timing_worst_paths.rpt

puts "=============================================="
puts "SYNTHESIS + IMPLEMENTATION COMPLETE"
puts "Reports written to: $report_dir"
puts "=============================================="

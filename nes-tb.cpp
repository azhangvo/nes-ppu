#include "obj_dir/Vnes_tb.h"
#include "verilated.h"

#include <iostream>

using namespace std;

VerilatedContext *contextp;

void run_for_cycles(Vnes_tb *dut, int cycles) {
    for (int i = 0; i < cycles * 2; i++) {
        dut->clk = i % 2;
        dut->eval();
    }
}

int main(int argc, char **argv) {
    contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    auto *dut = new Vnes_tb{contextp};
    Verilated::traceEverOn(true);

    dut->write_enable = 0;
    dut->reset = 1;
    dut->ce = 0;
    run_for_cycles(dut, 1);

    dut->reset = 0;
    run_for_cycles(dut, 2);
    
    dut->ce = 1;

    run_for_cycles(dut, 100000);

    dut->write_enable = 1;

    run_for_cycles(dut, 1);

    fflush(stdout);
    delete contextp;
}
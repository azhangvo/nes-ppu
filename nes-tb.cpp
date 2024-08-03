#include "obj_dir/Vnes_tb.h"
#include "verilated.h"

#include <iostream>

using namespace std;

VerilatedContext *contextp;

int num_cycles = 0;

void write_image(Vnes_tb* dut) {
    dut->write_enable = 1;
    dut->eval();
    dut->write_enable = 0;
}

void reset_cycles(Vnes_tb* dut) {
    printf("Resetting cycles: %d -> %d\n", num_cycles, 0);
    num_cycles = 0;
    dut->cycle_count = num_cycles;
}

void run_for_cycles(Vnes_tb* dut, int cycles) {
    for (int i = 0; i < cycles * 2; i++) {
        dut->clk = i % 2;
        dut->eval();
        if(i % 2 == 1) {
            num_cycles++;
            dut->cycle_count = num_cycles;
            if(num_cycles % 10000 == 0) {
                cout << "Cycle: " << num_cycles << endl;
                write_image(dut);
            }
        }
    }
}

int main(int argc, char** argv) {
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

    reset_cycles(dut);

    write_image(dut);

    run_for_cycles(dut, 100000);

    fflush(stdout);
    delete contextp;
}
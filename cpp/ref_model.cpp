#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <map>
#include <vector>
#include <random>
#include "time.h"


class togawa_refmode{

    enum opcode{
        WA_indirect,
        WA_direct,
        TOGA,
    };
    struct inst_t{
        opcode opc;
        size_t addr;
        size_t mask_idx;
        int pc_delta;
    };

    uint64_t reg;
    size_t pc;
    std::vector<char> mem;
    std::vector<inst_t> prog;

    void load_addr(size_t addr) {
        // Extend addr into 64bit alignment
        size_t byte_addr = addr * 8;
        uint64_t ret = 0;
        for(int i=0; i < 8; i++) {
            ret |= mem[i];
            ret = ret << 8;
        }

        reg = ret;
    }

    bool flip_and_decide(size_t mask_idx) {
        int byte_idx = mask_idx / 8;
        int bit_idx = mask_idx % 8;
        //flip corresponding bit and return if should take branch;
        return false;
    }

    public:
    void init_prog() {

        /*
         * Randomize instruction generation for fuzzing
         */
        srand(time(NULL));
        for(int i=0; i < 1000; i++) {
            int rand_int = rand() % 3;
            inst_t new_inst;
            if(rand_int == 0) {
                new_inst.opc = opcode::TOGA;
                new_inst.mask_idx = rand() % 64;
                new_inst.pc_delta = rand() % 1000;
            } else if(rand_int == 1) {
                new_inst.opc = opcode::WA_direct;
                new_inst.addr = rand() % 1024;
            }else {
                new_inst.opc = opcode::WA_indirect;
            }
            prog.push_back(new_inst);
        }
    }


    void tick() {
        auto iter = prog.begin() + pc;
        if (iter->opc == opcode::TOGA) {
            if(flip_and_decide(iter->mask_idx)){
                pc += iter->pc_delta;
            } else {
                pc += 1;
            }
        } else if(iter->opc == opcode::WA_direct) {
            load_addr(iter->addr);
        } else {
            load_addr(static_cast<size_t>(reg));
        }
    }

};

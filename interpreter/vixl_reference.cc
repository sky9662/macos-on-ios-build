// Fixed, independently authored fixtures only. VIXL is an instruction
// simulator, not a sandbox for untrusted guest code. Never accept an input file.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "aarch64/simulator-aarch64.h"
extern "C" {
#include "arm64_subset.h"
}
using namespace vixl::aarch64;

static const uint32_t adder[]={0x4a010003,0x0a010004,0x0a020065,0x2a050081,
                              0x4a020060,0x2a010400,0xd65f03c0};
static const uint32_t cmp[]={0xf100141f,0x54000062,0xd2800020,0xd65f03c0,
                             0xd2800040,0xd65f03c0};
static const uint32_t wide[]={0xca010000,0x91000400,0xaa00fc00,0xd65f03c0};
static const uint32_t multiply[]={0x9b017c00,0xd65f03c0};
static void require(bool ok) { if (!ok) std::abort(); }

template<size_t N>
static void compare(Simulator& sim,const uint32_t (&words)[N],
                    uint64_t a,uint64_t b,uint64_t c,uint64_t expected) {
    TCRegisters state={};
    state.x[0]=a;state.x[1]=b;state.x[2]=c;
    require(tc_interpret(words,N,&state,nullptr,0,32)==TC_OK);
    require(state.x[0]==expected);
    sim.WriteXRegister(0,a);
    sim.WriteXRegister(1,b);
    sim.WriteXRegister(2,c);
    sim.RunFrom(reinterpret_cast<const Instruction*>(words));
    require(static_cast<uint64_t>(sim.ReadXRegister(0))==expected);
}
int main() {
    Decoder decoder;
    Simulator sim(&decoder);
    for(uint64_t a=0;a<2;a++) for(uint64_t b=0;b<2;b++) for(uint64_t c=0;c<2;c++)
        compare(sim,adder,a,b,c,a+b+c);
    for(uint64_t i=0;i<1024;i++) {
        compare(sim,cmp,i,0,0,i>=5?2:1);
        uint64_t a=UINT64_C(0x1234567800000000)+i,b=UINT64_C(0x23456789abcdef00)-i;
        uint64_t expected=(a^b)+1; expected|=expected<<63;
        compare(sim,wide,a,b,0,expected);
    }
    // MUL is outside our bounded subset. Verify its rejection and that the
    // established engine covers the independently authored instruction.
    for(uint64_t i=0;i<128;i++) {
        TCRegisters state={};state.x[0]=i;state.x[1]=19;
        require(tc_interpret(multiply,2,&state,nullptr,0,16)==TC_UNSUPPORTED);
        sim.WriteXRegister(0,i);
        sim.WriteXRegister(1,19);
        sim.RunFrom(reinterpret_cast<const Instruction*>(multiply));
        require(static_cast<uint64_t>(sim.ReadXRegister(0))==i*19);
    }
    std::puts("PASS: VIXL vs bounded subset: 2056 shared cases; 128 extra MUL cases");
}

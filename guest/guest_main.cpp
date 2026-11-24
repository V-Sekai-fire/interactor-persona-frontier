// The guest of the time-sliced, distributed solver: the Slang `solve` kernel (as C++) run by a host through libriscv.
// Syscalls (host side in host/turbo_host.cpp): 500 problem text, 501 await a subproblem, 502 result.
#include "slang-cpp-prelude.h"
#include <cstdlib>
#include <climits>
#include <vector>

struct Span { void* data; size_t count; };
struct Globals { Span lower, upper, root_lower, root_upper, snap_lower, snap_upper, best_lower, best_upper, code, strategies, strategy_vars, decisions, state, control; };
extern "C" void solve(ComputeVaryingInput*, void*, void*);

static const int STATE = 24;
static const int PHASE = 16;
static const int PHASE_DONE = 5;

static long call(long number, long a, long b, long c) {
    register long a7 __asm__("a7") = number;
    register long a0 __asm__("a0") = a;
    register long a1 __asm__("a1") = b;
    register long a2 __asm__("a2") = c;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a7), "r"(a1), "r"(a2) : "memory");
    return a0;
}

int main() {
    long size = call(500, 0, 0, 0);
    std::vector<char> text(size + 1);
    call(500, (long)text.data(), size, 0);
    text[size] = 0;
    const char* at = text.data();
    auto next = [&]() { char* end; long v = strtol(at, &end, 10); at = end; return (int)v; };
    int h[10];
    for (int i = 0; i < 10; ++i) h[i] = next();
    int n = h[0], m = h[1], ns = h[2], objective = h[3], power = h[4], max_depth = h[5], nvars = h[9];
    std::vector<int> root_lower(n), root_upper(n), code(4 * m), strategies(4 * ns), strategy_vars(nvars);
    for (int i = 0; i < n; ++i) { root_lower[i] = next(); root_upper[i] = next(); }
    for (auto& x : code) x = next();
    for (auto& x : strategies) x = next();
    for (auto& x : strategy_vars) x = next();
    std::vector<int> lower(n), upper(n), snap_lower(n), snap_upper(n), best_lower(n), best_upper(n);
    std::vector<int> decisions((size_t)max_depth * 8), state(STATE, 0), control(16, 0);
    control[0] = m; control[1] = n; control[2] = ns; control[3] = objective; control[4] = power; control[5] = max_depth;
    control[6] = 1; control[7] = h[7]; control[8] = h[8]; control[11] = INT_MAX; control[14] = 1;
    Globals g{{lower.data(), (size_t)n}, {upper.data(), (size_t)n}, {root_lower.data(), (size_t)n}, {root_upper.data(), (size_t)n},
      {snap_lower.data(), (size_t)n}, {snap_upper.data(), (size_t)n}, {best_lower.data(), (size_t)n}, {best_upper.data(), (size_t)n},
      {code.data(), (size_t)m}, {strategies.data(), (size_t)ns}, {strategy_vars.data(), strategy_vars.size()},
      {decisions.data(), decisions.size()}, {state.data(), state.size()}, {control.data(), control.size()}};
    ComputeVaryingInput input = {};
    input.startGroupID = {0, 0, 0};
    input.endGroupID = {1, 1, 1};
    for (;;) {
        solve(&input, nullptr, &g);
        if (state[PHASE] == PHASE_DONE) break;
        call(501, (long)control.data(), (long)state.data(), 0);
    }
    call(502, (long)best_lower.data(), (long)best_upper.data(), (long)state.data());
    return 0;
}

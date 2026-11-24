// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2025 Pierre Talbot
// SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
// SPDX-License-Identifier: Apache-2.0 AND MIT
// Runs the cooperative Slang solver (turbo/Turbo/Coop.lean, compiled to a cubin) on the GPU in short bounded launches.
// Usage: turbo_gpu KERNEL.cubin INPUT.txt BLOCKS SLICE_NODES [PAUSE_MS]
// TURBO_SERVE=1 keeps the process resident and reads commands on standard input, one per line, answering one line each:
//   run N      do at most N launches (fewer when the search is done); reply "status running|done nodes X approx A launches L"
//   status     the same reply without launching
//   save PATH  write the search state (stores, snapshots, best stores, decisions, state, control) to a file;  load PATH  read it back
//   result     print the final report (as the one-shot mode does) and exit;  quit  exit
// TURBO_GPU_DUTY (percent, default 100) caps this process's share of the GPU: after a launch that took d ms the host sleeps d * (100 / duty - 1) ms, so a game rendering at 64 Hz gets the card in between.
// INPUT.txt is the problem text of tools/turbo_solve.exs (header of ten integers, the store, the bytecodes, the strategies). Each launch advances every block by at most
// SLICE_NODES nodes, so one launch is short; the host sleeps PAUSE_MS between launches. Output is the format of the CPU driver, plus launch statistics.
#include <cuda.h>
#include <chrono>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <algorithm>
#include <vector>

#define CHECK(call) do { CUresult r_ = (call); if (r_ != CUDA_SUCCESS) { const char* m_ = nullptr; cuGetErrorString(r_, &m_); fprintf(stderr, "%s:%d %s: %s\n", __FILE__, __LINE__, #call, m_ ? m_ : "?"); return 2; } } while (0)

struct Span { void* data; size_t count; };
struct Globals { Span lower, upper, root_lower, root_upper, snap_lower, snap_upper, best_lower, best_upper, code, strategies, strategy_vars, decisions, state, control, active; };
static const int STATE = 24;

template <class T> static CUdeviceptr upload(const std::vector<T>& v) {
    CUdeviceptr d = 0;
    size_t bytes = std::max<size_t>(v.size() * sizeof(T), 4);
    if (cuMemAlloc(&d, bytes) != CUDA_SUCCESS) return 0;
    cuMemsetD8(d, 0, bytes);
    if (!v.empty()) cuMemcpyHtoD(d, v.data(), v.size() * sizeof(T));
    return d;
}

int main(int argc, char** argv) {
    if (argc < 5) { fprintf(stderr, "usage: %s kernel.cubin input.txt blocks slice_nodes [pause_ms]\n", argv[0]); return 2; }
    int blocks = atoi(argv[3]), slice = atoi(argv[4]), pause_ms = argc > 5 ? atoi(argv[5]) : 0;
    FILE* in = fopen(argv[2], "r");
    if (!in) return 2;
    int h[10];
    for (int i = 0; i < 10; ++i) if (fscanf(in, "%d", &h[i]) != 1) return 2;
    int n = h[0], m = h[1], ns = h[2], objective = h[3], power = h[4], max_depth = h[5], nvars = h[9];
    std::vector<int> root_lower(n), root_upper(n), code(4 * m), strategies(4 * ns), strategy_vars(nvars);
    for (int i = 0; i < n; ++i) if (fscanf(in, "%d %d", &root_lower[i], &root_upper[i]) != 2) return 2;
    for (auto& x : code) if (fscanf(in, "%d", &x) != 1) return 2;
    for (auto& x : strategies) if (fscanf(in, "%d", &x) != 1) return 2;
    for (auto& x : strategy_vars) if (fscanf(in, "%d", &x) != 1) return 2;
    fclose(in);
    size_t cells = (size_t)blocks * n;
    std::vector<int> zeros_active((size_t)blocks * 2 * m, 0), zeros_cells(cells, 0), decisions((size_t)blocks * max_depth * 8, 0), state((size_t)blocks * STATE, 0), control(16, 0);
    control[0] = m; control[1] = n; control[2] = ns; control[3] = objective; control[4] = power; control[5] = max_depth;
    control[6] = blocks; control[7] = h[7]; control[8] = h[8]; control[10] = blocks; control[11] = INT_MAX; control[13] = slice;

    CHECK(cuInit(0));
    CUdevice dev; CHECK(cuDeviceGet(&dev, 0));
    CUcontext ctx; CHECK(cuCtxCreate(&ctx, 0, dev));
    CUmodule mod; CHECK(cuModuleLoad(&mod, argv[1]));
    CUfunction fn; CHECK(cuModuleGetFunction(&fn, mod, "solve"));
    CUdeviceptr gp; size_t gsize;
    CHECK(cuModuleGetGlobal(&gp, &gsize, mod, "SLANG_globalParams"));
    // 224 bytes: fourteen buffers; 240 bytes: a fifteenth, the per-block list of active propagators.
    if (gsize != sizeof(Globals) && gsize != sizeof(Globals) - sizeof(Span)) { fprintf(stderr, "global parameter block is %zu bytes, expected %zu or %zu\n", gsize, sizeof(Globals), sizeof(Globals) - sizeof(Span)); return 2; }
    CUdeviceptr d_lower = upload(zeros_cells), d_upper = upload(zeros_cells), d_rl = upload(root_lower), d_ru = upload(root_upper);
    CUdeviceptr d_sl = upload(zeros_cells), d_su = upload(zeros_cells), d_bl = upload(zeros_cells), d_bu = upload(zeros_cells);
    CUdeviceptr d_active = upload(zeros_active);
    CUdeviceptr d_code = upload(code), d_str = upload(strategies), d_sv = upload(strategy_vars), d_dec = upload(decisions), d_state = upload(state), d_ctl = upload(control);
    if (!d_lower || !d_upper || !d_sl || !d_su || !d_bl || !d_bu || !d_dec) { fprintf(stderr, "out of device memory for %d blocks\n", blocks); return 2; }
    Globals g{{(void*)d_lower, cells}, {(void*)d_upper, cells}, {(void*)d_rl, (size_t)n}, {(void*)d_ru, (size_t)n}, {(void*)d_sl, cells}, {(void*)d_su, cells},
              {(void*)d_bl, cells}, {(void*)d_bu, cells}, {(void*)d_code, (size_t)m}, {(void*)d_str, (size_t)ns}, {(void*)d_sv, strategy_vars.size()},
              {(void*)d_dec, decisions.size()}, {(void*)d_state, state.size()}, {(void*)d_ctl, control.size()}, {(void*)d_active, zeros_active.size()}};
    CHECK(cuMemcpyHtoD(gp, &g, gsize));

    using clk = std::chrono::steady_clock;
    const double duty = getenv("TURBO_GPU_DUTY") ? atof(getenv("TURBO_GPU_DUTY")) : 100.0;
    auto start = clk::now();
    int launches = 0;
    double max_ms = 0, sum_ms = 0;
        bool done = false;
    int last_approx = INT_MAX;
    auto step = [&](int max_this_call) -> int {
        int did = 0;
        while (!done && did < max_this_call) {
            auto t0 = clk::now();
            if (cuLaunchKernel(fn, blocks, 1, 1, 256, 1, 1, 0, 0, nullptr, nullptr) != CUDA_SUCCESS || cuCtxSynchronize() != CUDA_SUCCESS) { fprintf(stderr, "launch failed\n"); return -1; }
            double ms = std::chrono::duration<double, std::milli>(clk::now() - t0).count();
            launches++; did++; sum_ms += ms; if (ms > max_ms) max_ms = ms;
            cuMemcpyDtoH(state.data(), d_state, state.size() * sizeof(int));
            done = true;
            int finished = 0;
            long total_nodes = 0;
            for (int b = 0; b < blocks; ++b) { if (state[b * STATE + 16] != 5) done = false; else finished++; total_nodes += state[b * STATE + 7]; }
            int approx = 0;
            cuMemcpyDtoH(&approx, d_ctl + 11 * sizeof(int), sizeof(int));
            if (approx != last_approx) {
                last_approx = approx;
                fprintf(stderr, "best bound %d at %.1f ms (launch %d, %ld nodes)\n", approx, std::chrono::duration<double, std::milli>(clk::now() - start).count(), launches, total_nodes);
            }
            if (getenv("TURBO_PROGRESS") && launches % atoi(getenv("TURBO_PROGRESS")) == 0)
                fprintf(stderr, "launch %d: %ld nodes, %d of %d blocks done, best bound %d\n", launches, total_nodes, finished, blocks, approx);
            if (!done && pause_ms) std::this_thread::sleep_for(std::chrono::milliseconds(pause_ms));
            if (!done && duty < 100.0) std::this_thread::sleep_for(std::chrono::duration<double, std::milli>(ms * (100.0 / duty - 1.0)));
        }
        return did;
    };
    auto status_line = [&]() {
        long nodes = 0;
        for (int b = 0; b < blocks; ++b) nodes += state[b * STATE + 7];
        printf("status %s nodes %ld approx %d launches %d\n", done ? "done" : "running", nodes, last_approx, launches);
        fflush(stdout);
    };
    auto save_all = [&](const char* path, bool writing) -> bool {
        FILE* f = fopen(path, writing ? "wb" : "rb");
        if (!f) return false;
        std::vector<int> tmp;
        bool ok = true;
        auto copy = [&](CUdeviceptr d, size_t ints) {
            tmp.resize(ints);
            if (writing) { cuMemcpyDtoH(tmp.data(), d, ints * sizeof(int)); ok = ok && fwrite(tmp.data(), sizeof(int), ints, f) == ints; }
            else { ok = ok && fread(tmp.data(), sizeof(int), ints, f) == ints; if (ok) cuMemcpyHtoD(d, tmp.data(), ints * sizeof(int)); }
        };
        copy(d_lower, cells); copy(d_upper, cells); copy(d_sl, cells); copy(d_su, cells); copy(d_bl, cells); copy(d_bu, cells);
        copy(d_dec, decisions.size()); copy(d_state, state.size()); copy(d_ctl, control.size());
        fclose(f);
        if (!writing) { cuMemcpyDtoH(state.data(), d_state, state.size() * sizeof(int)); }
        return ok;
    };
    if (getenv("TURBO_SERVE")) {
        char line[512];
        while (fgets(line, sizeof line, stdin)) {
            int count = 0; char path[400];
            if (sscanf(line, "run %d", &count) == 1) { if (step(count) < 0) return 2; status_line(); }
            else if (!strncmp(line, "status", 6)) status_line();
            else if (sscanf(line, "save %399s", path) == 1) { printf(save_all(path, true) ? "saved\n" : "save failed\n"); fflush(stdout); }
            else if (sscanf(line, "load %399s", path) == 1) { printf(save_all(path, false) ? "loaded\n" : "load failed\n"); fflush(stdout); }
            else if (!strncmp(line, "result", 6)) break;
            else if (!strncmp(line, "quit", 4)) return 0;
        }
    }
    else {
        const int max_launches = getenv("TURBO_MAX_LAUNCHES") ? atoi(getenv("TURBO_MAX_LAUNCHES")) : INT_MAX;
        if (step(max_launches) < 0) return 2;
    }
    double wall = std::chrono::duration<double, std::milli>(clk::now() - start).count();
    CHECK(cuMemcpyDtoH(control.data(), d_ctl, control.size() * sizeof(int)));
    if (!done) {
        printf("status running after %d launches\n", launches);
        std::vector<std::pair<int, int>> order;
        for (int b = 0; b < blocks; ++b) order.push_back({state[b * STATE + 7], b});
        std::sort(order.rbegin(), order.rend());
        for (int k = 0; k < 8 && k < blocks; ++k) {
            int* s = &state[order[k].second * STATE];
            printf("busiest block %d: phase %d subproblem %d nodes %d fails %d solutions %d depth %d depth_max %d remaining %d\n", order[k].second, s[16], s[9], s[7], s[8], s[6], s[0], s[11], s[15]);
        }
        return 0;
    }
    long nodes = 0;
    for (int b = 0; b < blocks; ++b) nodes += state[b * STATE + 7];
    printf("status done nodes %ld\n", nodes);
    printf("gpu launches %d wall %.1f ms mean %.3f ms max %.3f ms\n", launches, wall, sum_ms / launches, max_ms);
    printf("error %d approx %d next %d\n", control[12], control[11], control[10]);
    int best = -1;
    for (int b = 0; b < blocks; ++b) {
        int* s = &state[b * STATE];
        if (s[6] > 0 || b < 4) printf("block %d solutions %d bound %d nodes %d fails %d depth_max %d exhaustive %d\n", b, s[6], s[5], s[7], s[8], s[11], s[10]);
        if (s[6] > 0 && (best < 0 || s[5] < state[best * STATE + 5])) best = b;
    }
    printf("best %d\n", best);
    if (best >= 0) {
        std::vector<int> bl(n), bu(n);
        CHECK(cuMemcpyDtoH(bl.data(), d_bl + (size_t)best * n * sizeof(int), n * sizeof(int)));
        CHECK(cuMemcpyDtoH(bu.data(), d_bu + (size_t)best * n * sizeof(int), n * sizeof(int)));
        for (int i = 0; i < n; ++i) printf("%d %d\n", bl[i], bu[i]);
    }
    return 0;
}

// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2025 Pierre Talbot
// SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
// SPDX-License-Identifier: Apache-2.0 AND MIT
// Runs the solver guest ELF under libriscv and talks to a worker node over stdin and stdout in length-prefixed frames (an Erlang Port with {packet, 4}).
// host to worker: "H" hello | "A skip bound solutions nodes" (the guest waits for a subproblem; the four numbers are the answer of the subproblem it just ran) | "U bound" a better bound than the last report | "R nodes fails solutions bound depth_max exhaustive" then n lines "lower upper"
// worker to host: "P" problem text | "S index bound" assign a subproblem | "D" no more subproblems | "B bound" a better bound found elsewhere | "C" cancel the subproblem in hand (another node finished it) | "X" stop
// TURBO_FRAME_MS (compute time per frame) and TURBO_FRAME_HZ (default 64) run the guest in frames: each window gets an instruction budget calibrated to that compute time, then the host sleeps to the next frame edge; window statistics go to stderr at exit.
// TURBO_SLEEP_US makes the host sleep that long after every budget window, to imitate a slower node.
#include <libriscv/machine.hpp>
#include <fstream>
#include <iostream>
#include <poll.h>
#include <unistd.h>
#include <cstdint>
#include <cstring>
#include <climits>
#include <string>
#include <vector>
#include <chrono>
#include <thread>
using namespace riscv;
using M = Machine<RISCV64>;
static const int STATE = 24;

static bool read_all(void* data, size_t len) {
	uint8_t* p = static_cast<uint8_t*>(data);
	while (len) { ssize_t r = read(0, p, len); if (r <= 0) return false; p += r; len -= r; }
	return true;
}
static bool read_frame(std::string& out) {
	uint8_t head[4];
	if (!read_all(head, 4)) return false;
	uint32_t len = (uint32_t(head[0]) << 24) | (uint32_t(head[1]) << 16) | (uint32_t(head[2]) << 8) | head[3];
	out.resize(len);
	return len == 0 || read_all(out.data(), len);
}
static void write_frame(const std::string& s) {
	uint8_t head[4] = {uint8_t(s.size() >> 24), uint8_t(s.size() >> 16), uint8_t(s.size() >> 8), uint8_t(s.size())};
	fwrite(head, 1, 4, stdout);
	fwrite(s.data(), 1, s.size(), stdout);
	fflush(stdout);
}
static bool input_waiting() { pollfd f{0, POLLIN, 0}; return poll(&f, 1, 0) > 0; }

struct Link {
	std::string problem;
	uint64_t control = 0, state = 0;
	int bound = INT_MAX;
	int reported = INT_MAX;
	int solutions_before = 0, nodes_before = 0; // the guest's running counters when the job in hand began
	bool stop = false;
};
static Link lnk;
static int geti(M& m, uint64_t addr, int index) { int v; m.copy_from_guest(&v, addr + 4 * index, 4); return v; }
static void puti(M& m, uint64_t addr, int index, int v) { m.copy_to_guest(addr + 4 * index, &v, 4); }
// A bound from elsewhere tightens control[11] (the grid's approximate best bound).
static void apply_bound(M& m, Link& l, int bound) {
	if (bound < l.bound) l.bound = bound;
	if (l.control && l.bound < geti(m, l.control, 11)) puti(m, l.control, 11, l.bound);
}
// A subproblem's answer must depend only on the problem, the subproblem's index and the bound it is assigned with, so that any node can replay it and a different
// answer is a proof of a fault. Everything the guest keeps from one subproblem to the next and that the search or the answer reads is set here, and nowhere else:
//   control[10]  the first subproblem not made unreachable (a running maximum in the guest: the answer's `skip` is this subproblem's alone)
//   control[11]  the approximate best bound, and state[5] the block's own best: both become the assigned bound
//   control[15]  the cancel request
// The counters (state[6] solutions, state[7] nodes) keep running in the guest; their values at the start of the job are kept here, and the waiting frame reports the
// differences, so an answer carries this subproblem's counts and nothing of the ones before. tools/cluster_replay.exs checks the property itself: every subproblem,
// on three hosts, in three different orders, gives the same answer.
static void begin_job(M& m, Link& l, uint64_t control, uint64_t state, int index, int bound) {
	l.bound = bound;
	puti(m, control, 10, 0);
	puti(m, control, 11, bound);
	puti(m, control, 15, 0);
	puti(m, state, 5, bound);
	puti(m, state, 9, index);
	puti(m, state, 16, 1);
	l.solutions_before = geti(m, state, 6);
	l.nodes_before = geti(m, state, 7);
}

int main(int argc, char** argv) {
	if (argc < 2) { std::cerr << argv[0] << " guest.elf [budget]\n"; return 2; }
	uint64_t budget = argc > 2 ? std::stoull(argv[2]) : UINT64_MAX;
	useconds_t sleep_us = getenv("TURBO_SLEEP_US") ? atoi(getenv("TURBO_SLEEP_US")) : 0;
	std::ifstream stream(argv[1], std::ios::in | std::ios::binary);
	const std::vector<uint8_t> binary((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
	M machine{binary, {.memory_max = 6ull << 30, .ignore_text_section = true}};
	machine.setup_linux_syscalls();
	machine.setup_linux({"turbo_guest"}, {"LC_ALL=C"});
	M::install_syscall_handler(500, [](M& m) {
		auto [ptr, len] = m.sysargs<uint64_t, uint64_t>();
		if (ptr) m.copy_to_guest(ptr, lnk.problem.data(), std::min<uint64_t>(len, lnk.problem.size()));
		m.set_result(int64_t(lnk.problem.size()));
	});
	M::install_syscall_handler(501, [](M& m) {
		auto [control, state] = m.sysargs<uint64_t, uint64_t>();
		lnk.control = control; lnk.state = state;
		write_frame("A " + std::to_string(geti(m, control, 10)) + " " + std::to_string(geti(m, state, 5)) + " " + std::to_string(geti(m, state, 6) - lnk.solutions_before) + " " + std::to_string(geti(m, state, 7) - lnk.nodes_before));
		for (;;) {
			std::string frame;
			if (!read_frame(frame) || frame[0] == 'X') { lnk.stop = true; m.stop(); return; }
			if (frame[0] == 'B') { apply_bound(m, lnk, std::stoi(frame.substr(2))); continue; }
			if (frame[0] == 'S') {
				int index, bound;
				sscanf(frame.c_str() + 2, "%d %d", &index, &bound);
				begin_job(m, lnk, control, state, index, bound);
				return;
			}
			if (frame[0] == 'D') { puti(m, state, 16, 5); return; }
			// a cancel that arrives while the guest waits has nothing to cancel
		}
	});
	M::install_syscall_handler(502, [](M& m) {
		auto [lower, upper, state] = m.sysargs<uint64_t, uint64_t, uint64_t>();
		int n = std::stoi(lnk.problem.substr(0, lnk.problem.find(' ')));
		std::string out = "R " + std::to_string(geti(m, state, 7)) + " " + std::to_string(geti(m, state, 8)) + " " + std::to_string(geti(m, state, 6)) + " " + std::to_string(geti(m, state, 5)) + " " + std::to_string(geti(m, state, 11)) + " " + std::to_string(geti(m, state, 10)) + "\n";
		std::vector<int> lo(n), up(n);
		m.copy_from_guest(lo.data(), lower, 4ull * n);
		m.copy_from_guest(up.data(), upper, 4ull * n);
		for (int i = 0; i < n; ++i) out += std::to_string(lo[i]) + " " + std::to_string(up[i]) + "\n";
		write_frame(out);
		m.stop();
	});
	write_frame("H");
	std::string frame;
	if (!read_frame(frame) || frame[0] != 'P') return 3;
	lnk.problem = frame.substr(2);
	if (getenv("TURBO_TRACE")) {
		std::vector<uint64_t> history;
		for (;;) {
			history.push_back(machine.cpu.pc());
			if (history.size() > 16) history.erase(history.begin());
			try { machine.cpu.step_one(); } catch (const MachineException& e) {
				std::cerr << "trace: " << e.what() << " last pcs:";
				for (auto pc : history) std::cerr << " " << std::hex << pc;
				std::cerr << std::dec << "\n";
				return 6;
			}
			if (machine.stopped()) {
				std::cerr << "trace: stopped, last pcs:";
				for (auto pc : history) std::cerr << " " << std::hex << pc;
				std::cerr << std::dec << " a0=" << machine.cpu.reg(10) << "\n";
				return 0;
			}
		}
	}
	using clk = std::chrono::steady_clock;
	const double frame_ms = getenv("TURBO_FRAME_MS") ? atof(getenv("TURBO_FRAME_MS")) : 0.0;
	const double hz = getenv("TURBO_FRAME_HZ") ? atof(getenv("TURBO_FRAME_HZ")) : 64.0;
	const auto period = std::chrono::duration_cast<clk::duration>(std::chrono::duration<double>(1.0 / hz));
	auto next_frame = clk::now() + period;
	if (frame_ms > 0) budget = 200000;
	struct { uint64_t windows = 0; double max_ms = 0, sum_ms = 0; uint64_t over = 0; uint64_t instructions = 0; } stats;
	auto window = [&](bool first) {
		uint64_t before = machine.instruction_counter();
		auto t0 = clk::now();
		if (first) machine.simulate<false>(budget); else machine.resume<false>(budget);
		double ms = std::chrono::duration<double, std::milli>(clk::now() - t0).count();
		uint64_t ran = machine.instruction_counter() - before;
		stats.windows++; stats.sum_ms += ms; stats.instructions += ran;
		if (ms > stats.max_ms) stats.max_ms = ms;
		if (frame_ms > 0) {
			if (ms > frame_ms * 1.5) stats.over++;
			if (ran > 1000 && ms > 0.01) budget = std::max<uint64_t>(50000, uint64_t(0.5 * budget + 0.5 * (double(ran) * frame_ms / ms)));
			std::this_thread::sleep_until(next_frame);
			next_frame += period;
			if (next_frame < clk::now()) next_frame = clk::now() + period;
		}
		if (sleep_us) usleep(sleep_us);
	};
	auto report = [&]() {
		if (stats.windows && frame_ms > 0)
			std::cerr << "frames: " << stats.windows << " windows, mean " << stats.sum_ms / stats.windows << " ms, max " << stats.max_ms << " ms, over 1.5x target (" << frame_ms << " ms): " << stats.over
			          << ", " << stats.instructions << " instructions, final budget " << budget << "\n";
	};
	try {
		window(true);
		while (machine.instruction_limit_reached() && !lnk.stop) {
			while (input_waiting()) {
				std::string extra;
				if (!read_frame(extra)) { report(); return 4; }
				if (extra[0] == 'B') apply_bound(machine, lnk, std::stoi(extra.substr(2)));
				else if (extra[0] == 'C' && lnk.control) puti(machine, lnk.control, 15, 1);
				else if (extra[0] == 'X') { report(); return 0; }
			}
			if (lnk.state) {
				int mine = geti(machine, lnk.state, 5);
				if (mine < lnk.reported) { lnk.reported = mine; write_frame("U " + std::to_string(mine)); }
			}
			window(false);
		}
		report();
	} catch (const MachineException& e) {
		std::cerr << "guest failed: " << e.what() << " data 0x" << std::hex << e.data() << " at pc 0x" << machine.cpu.pc() << std::dec << "\n";
		uint64_t slot = 0;
		machine.copy_from_guest(&slot, 0xa5270, 8);
		std::cerr << "got.plt slot 0x" << std::hex << slot << " ra 0x" << machine.cpu.reg(1) << " t3 0x" << machine.cpu.reg(28) << " a0 0x" << machine.cpu.reg(10) << std::dec << "\n";
		return 5;
	} catch (const std::exception& e) {
		std::cerr << "guest failed: " << e.what() << " at pc 0x" << std::hex << machine.cpu.pc() << std::dec << "\n";
		return 5;
	}
	return 0;
}

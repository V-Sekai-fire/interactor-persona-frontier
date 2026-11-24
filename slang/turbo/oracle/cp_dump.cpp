// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2025 Pierre Talbot
// SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
// SPDX-License-Identifier: Apache-2.0 AND MIT
// Runs Turbo's own preprocessing (CP<Itv>::preprocess: parse, ternarize, simplify) on a FlatZinc file and dumps the result for the Slang solver:
// the store, the bytecodes, the search strategies and the objective variable.
#include <iostream>
#include <sstream>
#include <fstream>
#include <string>
#include <vector>
#include <memory>
#include <format>
#include <algorithm>
#include <ranges>
#include <map>
#include <set>
#include <optional>
#include <functional>
#include <cassert>
#include <cstring>
#include <any>
#include <variant>
#include <tuple>
#include <mutex>
#include <thread>
#include <atomic>
#include <limits>
#include <cmath>
#include <array>
#include <utility>
#include <numeric>
#include <unordered_map>
#include <unordered_set>
#include <deque>
#include <list>
#include <span>
#include <bitset>
#include <type_traits>
#include <iomanip>
#include <chrono>
#include <random>
#include <csignal>
#include <cstdio>
#include <climits>
#include <cstdlib>
#define private public
#include "common_solving.hpp"
using namespace battery;

#define SIG_NAME(x) case x: return #x;
static const char* sig_name(lala::Sig sig) {
  using namespace lala;
  switch(sig) {
    SIG_NAME(NEG) SIG_NAME(ABS) SIG_NAME(ADD) SIG_NAME(SUB) SIG_NAME(MUL) SIG_NAME(POW) SIG_NAME(MIN) SIG_NAME(MAX)
    SIG_NAME(DIV) SIG_NAME(MOD) SIG_NAME(TDIV) SIG_NAME(TMOD) SIG_NAME(FDIV) SIG_NAME(FMOD) SIG_NAME(CDIV) SIG_NAME(CMOD) SIG_NAME(EDIV) SIG_NAME(EMOD)
    SIG_NAME(IN) SIG_NAME(SUBSET) SIG_NAME(SUBSETEQ) SIG_NAME(SUPSET) SIG_NAME(SUPSETEQ)
    SIG_NAME(EQ) SIG_NAME(NEQ) SIG_NAME(LEQ) SIG_NAME(GEQ) SIG_NAME(LT) SIG_NAME(GT)
    SIG_NAME(AND) SIG_NAME(OR) SIG_NAME(IMPLY) SIG_NAME(EQUIV) SIG_NAME(NOT) SIG_NAME(XOR) SIG_NAME(ITE) SIG_NAME(MAXIMIZE) SIG_NAME(MINIMIZE)
    default: return "OTHER";
  }
}
template <class F>
static std::string to_text(const F& f) {
  if(f.is(F::Z)) return std::to_string(f.z());
  if(f.is(F::B)) return f.b() ? "true" : "false";
  if(f.is(F::R)) return "R";
  if(f.is(F::S)) {
    std::string out = "{";
    const auto& set = f.s();
    for(size_t i = 0; i < set.size(); ++i) {
      if(i > 0) out += ",";
      out += to_text(battery::get<0>(set[i])) + ".." + to_text(battery::get<1>(set[i]));
    }
    return out + "}";
  }
  if(f.is(F::V)) return "#" + std::to_string(f.v().vid());
  if(f.is(F::LV)) return std::string(f.lv().data());
  if(f.is(F::E)) {
    const auto& so = battery::get<1>(f.exists());
    return "(E " + std::string(battery::get<0>(f.exists()).data()) + " " + (so.is_bool() ? "B" : so.is_int() ? "Z" : so.is_real() ? "R" : "S") + ")";
  }
  if(f.is(F::Seq)) {
    std::string out = std::string("(") + sig_name(f.sig());
    for(int i = 0; i < f.seq().size(); ++i) out += " " + to_text(f.seq(i));
    return out + ")";
  }
  std::string out = std::string("(ESEQ ") + std::string(f.esig().data());
  for(int i = 0; i < f.eseq().size(); ++i) out += " " + to_text(f.eseq()[i]);
  return out + ")";
}
int main(int argc, char** argv) {
  Configuration<standard_allocator> config = parse_args(argc, argv);
  CP<Itv> cp(config);
  if (const char* stage = getenv("TURBO_STAGE")) {
    using F = typename CP<Itv>::F;
    auto parsed = cp.parse_cn();
    F f = ternarize(*parsed, VarEnv<typename CP<Itv>::basic_allocator_type>(), {0,1,2});
    battery::vector<F> extra;
    f = normalize(f, extra);
    if(f.is(F::Seq) && f.sig() == lala::AND) {
      for(int i = 0; i < f.seq().size(); ++i) printf("%s\n", to_text(f.seq(i)).c_str());
    }
    else printf("%s\n", to_text(f).c_str());
    return 0;
  }
  cp.preprocess();
  if (const char* best_path = getenv("TURBO_BEST")) {
    std::ifstream in(best_path);
    std::string line;
    while (std::getline(in, line) && line.rfind("best", 0) != 0) {}
    cp.best->join_top();
    for (int i = 0; i < cp.best->vars(); ++i) {
      long lb, ub;
      in >> lb >> ub;
      cp.best->embed(i, Itv::local_type(lb, ub));
    }
    cp.print_solution(*cp.best);
    return 0;
  }
  auto& p = *cp.iprop;
  printf("bot %d\n", (int)p.is_bot());
  printf("variables %d\n", p.vars());
  for (int i = 0; i < p.vars(); ++i) printf("%d %d\n", p[i].lb().value(), p[i].ub().value());
  printf("bytecodes %d\n", (int)p.bytecodes->size());
  for (int i = 0; i < (int)p.bytecodes->size(); ++i) {
    auto& b = (*p.bytecodes)[i];
    printf("%s %d %d %d\n", string_of_sig(b.op), b.x.vid(), b.y.vid(), b.z.vid());
  }
  auto& strategies = cp.split->strategies_();
  printf("strategies %d\n", (int)strategies.size());
  for (int i = 0; i < (int)strategies.size(); ++i) {
    auto& s = strategies[i];
    printf("%d %d %d", (int)s.var_order, (int)s.val_order, (int)s.vars.size());
    for (int j = 0; j < (int)s.vars.size(); ++j) printf(" %d", s.vars[j].vid());
    printf("\n");
  }
  printf("objective %d %d\n", (int)cp.minimize_obj_var.is_untyped(), cp.minimize_obj_var.is_untyped() ? -1 : cp.minimize_obj_var.vid());
  printf("optimization %d %d\n", (int)cp.bab->is_minimization(), (int)cp.bab->is_maximization());
  if (!cp.bab->objective_var().is_untyped()) printf("bab_objective %d\n", cp.bab->objective_var().vid());
}

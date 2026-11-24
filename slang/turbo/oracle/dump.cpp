// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2025 Pierre Talbot
// SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
// SPDX-License-Identifier: Apache-2.0 AND MIT
// Reads a FlatZinc file, builds Turbo's PIR over a VStore of intervals, dumps store and bytecodes, runs the Gauss-Seidel fixpoint, dumps the store again.
#include <cstdio>
#include <climits>
#include <string>
#include <fstream>
#include <sstream>
#include <vector>
#include <memory>
#include <format>
#include <iostream>
#include <algorithm>
#include <ranges>
#include <map>
#include <set>
#include <optional>
#include <functional>
#include <cassert>
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
#include <deque>
#include <list>
#include <span>
#include <bitset>
#include <type_traits>
#include <iomanip>
#include <cstring>
#define private public
#include "abstract_testing.hpp"
#include "battery/vector.hpp"
#include "battery/shared_ptr.hpp"
#include "lala/vstore.hpp"
#include "lala/cartesian_product.hpp"
#include "lala/interval.hpp"
#include "lala/pir.hpp"
#include "lala/terms.hpp"
#include "lala/fixpoint.hpp"
using Itv = Interval<local::ZLB>;
using IStore = VStore<Itv, standard_allocator>;
using IPIR = PIR<IStore>;
static void store(const IPIR& p, const char* tag) {
  printf("%s %d\n", tag, p.vars());
  for (int i = 0; i < p.vars(); ++i) printf("%d %d\n", p[i].lb().value(), p[i].ub().value());
}
int main(int argc, char** argv) {
  std::ifstream in(argv[1]); std::stringstream ss; ss << in.rdbuf(); std::string fzn = ss.str();
  auto f = parse_flatzinc_str<standard_allocator>(fzn.c_str());
  if (!f) { fprintf(stderr, "parse failed\n"); return 2; }
  VarEnv<standard_allocator> env;
  *f = ternarize(*f, env);
  *f = normalize(*f);
  IDiagnostics diagnostics;
  auto value = create_and_interpret_and_tell<IPIR, true>(*f, env, diagnostics);
  diagnostics.print();
  if (!value.has_value()) { fprintf(stderr, "interpret failed\n"); return 3; }
  IPIR pir = std::move(value.value());
  store(pir, "store_before");
  printf("bytecodes %d\n", (int)pir.bytecodes->size());
  for (int i = 0; i < (int)pir.bytecodes->size(); ++i) {
    auto& b = (*pir.bytecodes)[i];
    printf("%s %d %d %d\n", string_of_sig(b.op), b.x.vid(), b.y.vid(), b.z.vid());
  }
  int rounds = 0;
  GaussSeidelIteration{}.fixpoint(pir.num_deductions(), [&](size_t i) { return pir.deduce(i); });
  store(pir, "store_after");
  printf("bot %d\n", (int)pir.is_bot());
}

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
int main(int argc, char** argv) {
  Configuration<standard_allocator> config = parse_args(argc, argv);
  CP<Itv> cp(config);
  cp.preprocess();
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

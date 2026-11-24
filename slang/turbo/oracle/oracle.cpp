#include "abstract_testing.hpp"
#include "battery/vector.hpp"
#include "battery/shared_ptr.hpp"
#include "lala/vstore.hpp"
#include "lala/cartesian_product.hpp"
#include "lala/interval.hpp"
#include "lala/pir.hpp"
#include "lala/terms.hpp"
#include <cstdio>
#include <climits>
#include <string>
using Itv = Interval<local::ZLB>;
using IStore = VStore<Itv, standard_allocator>;
using IPIR = PIR<IStore>;
int main() {
  const char* names[] = {"int_plus", "int_times", "int_min", "int_max", "int_div", "int_ediv", "int_mod", "int_eq_reif", "int_le_reif"};
  unsigned s = 12345;
  auto rnd = [&](int m) { s = s * 1103515245u + 12345u; return (int)((s >> 8) % m); };
  for (int k = 0; k < 9; ++k) for (int c = 0; c < 600; ++c) {
    int b[6];
    for (int i = 0; i < 3; ++i) { int a = rnd(17) - 8, d = rnd(17) - 8; b[2*i] = std::min(a, d); b[2*i+1] = std::max(a, d); }
    bool free_[3] = {rnd(6) == 0, rnd(6) == 0, rnd(6) == 0};
    if (k >= 7) { b[0] = rnd(3) == 0 ? 0 : (b[0] = 0, 0); b[1] = rnd(2); if (b[0] > b[1]) b[0] = b[1]; free_[0] = false; }
    for (int i = 0; i < 3; ++i) { if (k >= 4 && k <= 6) free_[i] = false; if (free_[i]) { b[2*i] = INT_MIN; b[2*i+1] = INT_MAX; } }
    auto dom = [&](int i) { return free_[i] ? std::string("int") : std::to_string(b[2*i]) + ".." + std::to_string(b[2*i+1]); };
    std::string fzn = std::string("var ") + dom(0) + ": x; var " + dom(1) + ": y; var " + dom(2) + ": z; constraint " + names[k] + "(y, z, x);";
    IPIR a = create_and_interpret_and_tell<IPIR, true>(fzn.c_str());
    a.deduce(0);
    fprintf(stderr, "%s %d %d %d %d %d %d | %d %d %d %d %d %d\n", names[k], b[0], b[1], b[2], b[3], b[4], b[5],
      a[0].lb().value(), a[0].ub().value(), a[1].lb().value(), a[1].ub().value(), a[2].lb().value(), a[2].ub().value());
  }
}

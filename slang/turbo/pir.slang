// Copy of lala_pc pir.hpp (ask, itv_div, num_*, den_*, mul_inv, deduce) and the battery division helpers. Names and structure kept.
// Lattice: lower bound meets by max, upper bound meets by min; join is the hull; bot is lb > ub; top is [MINF, INF].

static const int INF = 2147483647;
static const int MINF = -2147483647 - 1;

static const int ADD = 0;
static const int MUL = 1;
static const int MIN = 2;
static const int MAX = 3;
static const int EQ = 4;
static const int LEQ = 5;
static const int TDIV = 6;
static const int CDIV = 7;
static const int FDIV = 8;
static const int EDIV = 9;
static const int EMOD = 10;

int signum(int x) { return (x > 0 ? 1 : 0) - (x < 0 ? 1 : 0); }
int tdiv(int x, int y) { return x / y; }
int fdiv(int x, int y) { return x / y - (signum(x % y) == -signum(y) ? 1 : 0); }
int cdiv(int x, int y) { return x / y + (signum(x % y) == signum(y) ? 1 : 0); }
int ediv(int x, int y) { return x / y - ((x % y >= 0) ? 0 : signum(y)); }
int emod(int x, int y) { return x % y + y * ((x % y >= 0) ? 0 : signum(y)); }

struct Itv
{
    int lower;
    int upper;
    static Itv make(int l, int u) { Itv r; r.lower = l; r.upper = u; return r; }
    static Itv top() { return make(MINF, INF); }
    static Itv bot() { return make(INF, MINF); }
    bool is_top() { return lower == MINF && upper == INF; }
    bool is_bot() { return lower == INF || upper == MINF || (!is_top() && lower > upper); }
    // Returns true when the interval changed.
    [mutating] bool meet(Itv o)
    {
        int l = max(lower, o.lower);
        int u = min(upper, o.upper);
        bool changed = (l != lower) || (u != upper);
        lower = l; upper = u;
        return changed;
    }
    [mutating] void join(Itv o) { lower = min(lower, o.lower); upper = max(upper, o.upper); }
};

Itv fjoin(Itv a, Itv b)
{
    if (a.is_bot()) { return b; }
    if (b.is_bot()) { return a; }
    return Itv.make(min(a.lower, b.lower), max(a.upper, b.upper));
}

#define xl r1.lower
#define xu r1.upper
#define yl r2.lower
#define yu r2.upper
#define zl r3.lower
#define zu r3.upper

int div(int a, int op, int b)
{
    switch (op)
    {
    case TDIV: return tdiv(a, b);
    case CDIV: return cdiv(a, b);
    case FDIV: return fdiv(a, b);
    case EDIV: return ediv(a, b);
    default: return a;
    }
}

bool ask(int op, Itv r1, Itv r2, Itv r3)
{
    switch (op)
    {
    case EQ: return (xl == 1 && yu == zl && yl == zu) || (xu == 0 && (yu < zl || yl > zu));
    case LEQ: return (xl == 1 && yu <= zl) || (xu == 0 && yl > zu);
    case ADD: return (xl == xu && yl == yu && zl == zu && xl == yl + zl);
    case MUL: return xl == xu &&
                     ((yl == yu && zl == zu && xl == yl * zl)
                   || (xl == 0 && ((yl == 0 && yu == 0) || (zl == 0 && zu == 0))));
    case TDIV:
    case CDIV:
    case FDIV:
    case EDIV: return (xl == xu && yl == yu && zl == zu && zl != 0 && xl == div(yl, op, zl))
                   || (xl == yu && xu == yl && xl == 0 && (zl > 0 || zu < 0));
    case EMOD: return (xl == xu && yl == yu && zl == zu && zl != 0 && xl == emod(yl, zl));
    case MIN: return (xl == yu && xu == yl && yu <= zl) || (xl == zu && xu == zl && zu <= yl);
    case MAX: return (xl == yu && xu == yl && yl >= zu) || (xl == zu && xu == zl && zl >= yu);
    default: return false;
    }
}

// r1 = r2 / r3
void itv_div(int op, inout Itv r1, inout Itv r2, inout Itv r3)
{
    if (zl < 0 && zu > 0)
    {
        r1.lower = max(xl, min(yl, yu == MINF ? INF : -yu));
        r1.upper = min(xu, max(yl == INF ? MINF : -yl, yu));
    }
    else
    {
        if (zl == 0) { r3.lower = 1; }
        if (zu == 0) { r3.upper = -1; }
        if (yl == MINF || yu == INF || zl == MINF || zu == INF) { return; }
        if (r3.is_bot()) { return; }
        int t1 = div(yl, op, zl);
        int t2 = div(yl, op, zu);
        int t3 = div(yu, op, zl);
        int t4 = div(yu, op, zu);
        r1.lower = max(xl, min(min(t1, t2), min(t3, t4)));
        r1.upper = min(xu, max(max(t1, t2), max(t3, t4)));
    }
}

Itv num_fdiv(Itv r1, Itv r3)
{
    if (zl < 0 && zu > 0)
    {
        return Itv.make(min(min(xl, -xu), min(xl * zu, (xu + 1) * zl + 1)),
                        max(max(-xl, xu), max(xl * zl, (xu + 1) * zu - 1)));
    }
    else if (zl > 0 || zu < 0)
    {
        return Itv.make(min(min(xl * zl, xl * zu), min((xu + 1) * zl + 1, (xu + 1) * zu + 1)),
                        max(max(xl * zl, xl * zu), max((xu + 1) * zl - 1, (xu + 1) * zu - 1)));
    }
    return Itv.top();
}

Itv num_cdiv(Itv r1, Itv r3)
{
    if (zl < 0 && zu > 0)
    {
        return Itv.make(min(min(xl, -xu), min(xu * zl, (xl - 1) * zu + 1)),
                        max(max(-xl, xu), max(xu * zu, (xl - 1) * zl - 1)));
    }
    else if (zl > 0 || zu < 0)
    {
        return Itv.make(min(min(xu * zl, xu * zu), min((xl - 1) * zl + 1, (xl - 1) * zu + 1)),
                        max(max(xu * zl, xu * zu), max((xl - 1) * zl - 1, (xl - 1) * zu - 1)));
    }
    return Itv.top();
}

Itv num_tdiv(Itv r1, Itv r3)
{
    if (xl > 0)
    {
        return num_fdiv(r1, r3);
    }
    else if (xu < 0)
    {
        return num_cdiv(r1, r3);
    }
    else if (xl <= 0 && 0 <= xu)
    {
        Itv r = Itv.make(min(zl, -zu) + 1, max(-zl, zu) - 1);
        if (xl != 0) { r.join(num_cdiv(Itv.make(xl, -1), r3)); }
        if (xu != 0) { r.join(num_fdiv(Itv.make(1, xu), r3)); }
        return r;
    }
    return Itv.top();
}

// Lemma C.10
Itv num_ediv(Itv r1, Itv r3)
{
    if (zl > 0) { return num_fdiv(r1, r3); }
    else if (zu < 0) { return num_cdiv(r1, r3); }
    else if (zl < 0 && zu > 0)
    {
        return fjoin(num_cdiv(r1, Itv.make(zl, -1)), num_fdiv(r1, Itv.make(1, zu)));
    }
    return Itv.top();
}

// Lemma A.11 and C.12 (recursive in the source): three levels, the lowest one never recurses, see den_levels.slang.
Itv den_fdiv_below(Itv r1, Itv r2) { return Itv.top(); }
Itv den_cdiv_below(Itv r1, Itv r2) { return Itv.top(); }
#define SELF_FDIV den_fdiv0
#define SELF_CDIV den_cdiv0
#define NEXT_FDIV den_fdiv_below
#define NEXT_CDIV den_cdiv_below
#include "den_levels.slang"
#undef SELF_FDIV
#undef SELF_CDIV
#undef NEXT_FDIV
#undef NEXT_CDIV
#define SELF_FDIV den_fdiv1
#define SELF_CDIV den_cdiv1
#define NEXT_FDIV den_fdiv0
#define NEXT_CDIV den_cdiv0
#include "den_levels.slang"
#undef SELF_FDIV
#undef SELF_CDIV
#undef NEXT_FDIV
#undef NEXT_CDIV
#define SELF_FDIV den_fdiv
#define SELF_CDIV den_cdiv
#define NEXT_FDIV den_fdiv1
#define NEXT_CDIV den_cdiv1
#include "den_levels.slang"
#undef SELF_FDIV
#undef SELF_CDIV
#undef NEXT_FDIV
#undef NEXT_CDIV

// Lemma C.13: the source calls itself on x = [0, 0]; that case is den_tdiv_zero.
Itv den_tdiv_zero(Itv r1, Itv r2, Itv r3)
{
    if (yl > 0 && zl > 0) { return Itv.make(yl + 1, INF); }
    if (yl > 0 && zu < 0) { return Itv.make(MINF, -yl - 1); }
    if (yu < 0 && zl > 0) { return Itv.make(-yu + 1, INF); }
    if (yu < 0 && zu < 0) { return Itv.make(MINF, yu - 1); }
    return Itv.top();
}

Itv den_tdiv(Itv r1, Itv r2, Itv r3)
{
    if (xl > 0) { return den_fdiv(r1, r2); }
    else if (xu < 0) { return den_cdiv(r1, r2); }
    else if (xl == 0 && xu == 0) { return den_tdiv_zero(r1, r2, r3); }
    else if (xl <= 0 && 0 <= xu)
    {
        Itv r = den_tdiv_zero(Itv.make(0, 0), r2, r3);
        if (xl != 0) { r.join(den_cdiv(Itv.make(xl, -1), r2)); }
        if (xu != 0) { r.join(den_fdiv(Itv.make(1, xu), r2)); }
        return r;
    }
    return Itv.top();
}


Itv den_ediv(Itv r1, Itv r2, Itv r3)
{
    if (zl > 0) { return den_fdiv(r1, r2); }
    else if (zu < 0) { return den_cdiv(r1, r2); }
    else if (zl < 0 && 0 < zu)
    {
        return fjoin(den_fdiv(r1, r2), den_cdiv(r1, r2));
    }
    return Itv.top();
}

void itv_div_num(int op, Itv r1, inout Itv r2, Itv r3)
{
    switch (op)
    {
    case FDIV: { r2.meet(num_fdiv(r1, r3)); break; }
    case CDIV: { r2.meet(num_cdiv(r1, r3)); break; }
    case TDIV: { r2.meet(num_tdiv(r1, r3)); break; }
    case EDIV: { r2.meet(num_ediv(r1, r3)); break; }
    }
}

void itv_div_den(int op, Itv r1, Itv r2, inout Itv r3)
{
    switch (op)
    {
    case FDIV: { r3.meet(den_fdiv(r1, r2)); break; }
    case CDIV: { r3.meet(den_cdiv(r1, r2)); break; }
    case TDIV: { r3.meet(den_tdiv(r1, r2, r3)); break; }
    case EDIV: { r3.meet(den_ediv(r1, r2, r3)); break; }
    }
}

void mul_inv(Itv r1, inout Itv r2, inout Itv r3)
{
    if (xl > 0 || xu < 0)
    {
        if (zl == 0) { r3.lower = 1; }
        if (zu == 0) { r3.upper = -1; }
    }
    if ((xl > 0 || xu < 0) && zl < 0 && zu > 0)
    {
        r2.lower = max(yl, min(xl, xu == MINF ? INF : -xu));
        r2.upper = min(yu, max(xl == INF ? MINF : -xl, xu));
    }
    else if (xl > 0 || xu < 0 || zl > 0 || zu < 0)
    {
        if (xl == MINF || xu == INF || zl == MINF || zu == INF) { return; }
        if (r3.is_bot()) { return; }
        r2.lower = max(yl, min(min(cdiv(xl, zl), cdiv(xl, zu)), min(cdiv(xu, zl), cdiv(xu, zu))));
        r2.upper = min(yu, max(max(fdiv(xl, zl), fdiv(xl, zu)), max(fdiv(xu, zl), fdiv(xu, zu))));
    }
}

// The source embeds each result into the store; here the three intervals are the new store values and the caller meets them in.
// For EQ and LEQ the source returns early after embedding only part of the three, so the untouched ones are left as loaded.
void deduce(int op, inout Itv r1, inout Itv r2, inout Itv r3)
{
    int t1, t2, t3, t4;
    Itv ONE = Itv.make(1, 1);
    Itv ZERO = Itv.make(0, 0);
    Itv o1 = r1; Itv o2 = r2; Itv o3 = r3;
    switch (op)
    {
    case EQ:
    {
        if (o1.lower == 1 && o1.upper == 1) { r2.meet(o3); r3.meet(o2); }
        else if (o1.lower == 0 && o1.upper == 0 && (yl == yu || zl == zu))
        {
            Itv hole = Itv.make(yl == zl ? yl + 1 : MINF, yu == zu ? yu - 1 : INF);
            if (zl == zu) { r2.meet(hole); } else { r3.meet(hole); }
        }
        else if (yu == zl && yl == zu) { r1.meet(ONE); }
        else if (yl > zu || yu < zl) { r1.meet(ZERO); }
        return;
    }
    case LEQ:
    {
        if (o1.lower == 1 && o1.upper == 1)
        {
            r2.meet(Itv.make(yl, zu));
            r3.meet(Itv.make(yl, zu));
        }
        else if (o1.lower == 0 && o1.upper == 0)
        {
            r2.meet(Itv.make(zl + 1, yu));
            r3.meet(Itv.make(zl, yu - 1));
        }
        else if (yu <= zl) { r1.meet(ONE); }
        else if (yl > zu) { r1.meet(ZERO); }
        return;
    }
    case ADD:
    {
        Itv n1 = r1; Itv n2 = r2; Itv n3 = r3;
        n1.lower = (yl == MINF || zl == MINF) ? xl : max(xl, yl + zl);
        n1.upper = (yu == INF || zu == INF) ? xu : min(xu, yu + zu);
        n2.lower = (xl == MINF || zu == INF) ? yl : max(yl, xl - zu);
        n2.upper = (xu == INF || zl == MINF) ? yu : min(yu, xu - zl);
        n3.lower = (xl == MINF || yu == INF) ? zl : max(zl, xl - yu);
        n3.upper = (xu == INF || yl == MINF) ? zu : min(zu, xu - yl);
        r1.meet(n1); r2.meet(n2); r3.meet(n3);
        return;
    }
    case MUL:
    {
        Itv n1 = r1; Itv n2 = r2; Itv n3 = r3;
        if (yl != MINF && yu != INF && zl != MINF && zu != INF)
        {
            t1 = yl * zl;
            t2 = yl * zu;
            t3 = yu * zl;
            t4 = yu * zu;
            n1.lower = max(xl, min(min(t1, t2), min(t3, t4)));
            n1.upper = min(xu, max(max(t1, t2), max(t3, t4)));
        }
        mul_inv(n1, n2, n3);
        mul_inv(n1, n3, n2);
        r1.meet(n1); r2.meet(n2); r3.meet(n3);
        return;
    }
    case TDIV:
    case CDIV:
    case FDIV:
    case EDIV:
    {
        Itv n1 = r1; Itv n2 = r2; Itv n3 = r3;
        itv_div(op, n1, n2, n3);
        if (!n1.is_bot() && !n3.is_bot())
        {
            itv_div_num(op, n1, n2, n3);
            if (!n2.is_bot()) { itv_div_den(op, n1, n2, n3); }
        }
        r1.meet(n1); r2.meet(n2); r3.meet(n3);
        return;
    }
    case EMOD:
    {
        Itv n1 = r1; Itv n3 = r3;
        if (zl == 0) { n3.lower = 1; }
        if (zu == 0) { n3.upper = -1; }
        if (yl == yu && zl == zu)
        {
            n1.lower = emod(yl, zl);
            n1.upper = xl;
        }
        r1.meet(n1); r3.meet(n3);
        return;
    }
    case MIN:
    {
        Itv n1 = r1; Itv n2 = r2; Itv n3 = r3;
        n1.lower = max(xl, min(yl, zl));
        n1.upper = min(xu, min(yu, zu));
        n2.lower = max(yl, xl);
        if (xu < zl) { n2.upper = min(yu, xu); }
        n3.lower = max(zl, xl);
        if (xu < yl) { n3.upper = min(zu, xu); }
        r1.meet(n1); r2.meet(n2); r3.meet(n3);
        return;
    }
    case MAX:
    {
        Itv n1 = r1; Itv n2 = r2; Itv n3 = r3;
        n1.lower = max(xl, max(yl, zl));
        n1.upper = min(xu, max(yu, zu));
        n2.upper = min(yu, xu);
        if (xl > zu) { n2.lower = max(yl, xl); }
        n3.upper = min(zu, xu);
        if (xl > yu) { n3.lower = max(zl, xl); }
        r1.meet(n1); r2.meet(n2); r3.meet(n3);
        return;
    }
    default: return;
    }
}

#undef xl
#undef xu
#undef yl
#undef yu
#undef zl
#undef zu

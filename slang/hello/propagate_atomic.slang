// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: Apache-2.0 OR MIT
// x = y + z over interval domains; one thread per constraint. A hello kernel for the TNF port (not the real format).
struct Constraint { uint x; uint y; uint z; uint op; };   // op 0 = add
RWStructuredBuffer<int> lower;
RWStructuredBuffer<int> upper;
StructuredBuffer<Constraint> constraints;
RWStructuredBuffer<uint> changed;

[shader("compute")]
[numthreads(64, 1, 1)]
void propagate(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= 3) return;
    Constraint c = constraints[id.x];
    int nl = max(lower[c.x], lower[c.y] + lower[c.z]);
    int nu = min(upper[c.x], upper[c.y] + upper[c.z]);
    if (nl != lower[c.x] || nu != upper[c.x]) {
        InterlockedMax(lower[c.x], nl);
        InterlockedMin(upper[c.x], nu);
        uint old;
        InterlockedAdd(changed[0], 1, old);
    }
}

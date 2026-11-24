#include "pir.slang"
RWStructuredBuffer<int> cells;
[shader("compute")]
[numthreads(1, 1, 1)]
void probe(uint3 id : SV_DispatchThreadID)
{
    Itv a = Itv.make(cells[0], cells[1]);
    Itv b = Itv.make(cells[2], cells[3]);
    Itv c = Itv.make(cells[4], cells[5]);
    deduce(cells[6], a, b, c);
    cells[0] = a.lower; cells[1] = a.upper; cells[2] = b.lower; cells[3] = b.upper; cells[4] = c.lower; cells[5] = c.upper;
    cells[7] = ask(cells[6], a, b, c) ? 1 : 0;
}

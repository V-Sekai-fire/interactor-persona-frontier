// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2025 Pierre Talbot
// SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
// SPDX-License-Identifier: Apache-2.0 AND MIT
// Included three times by pir.slang: Turbo recurses in den_fdiv and den_cdiv, the compiler allows no recursion, so each level calls the one below it.
Itv SELF_FDIV(Itv r1, Itv r2)
{
    if (xl > 0 || xu + 1 < 0)
    {
        if (yl > 0)
        {
            return Itv.make(min(fdiv(yl, xu + 1), fdiv(yu, xu + 1)) + 1,
                            max(fdiv(yl, xl), fdiv(yu, xl)));
        }
        else if (yu < 0)
        {
            return Itv.make(min(cdiv(yl, xl), cdiv(yu, xl)),
                            max(cdiv(yl, xu + 1), cdiv(yu, xu + 1)) - 1);
        }
        else if (0 == yl && yl < yu)
        {
            return NEXT_FDIV(r1, Itv.make(1, yu));
        }
        else if (yl < yu && yu == 0)
        {
            return NEXT_FDIV(r1, Itv.make(yl, -1));
        }
        else if (yl < 0 && 0 < yu)
        {
            return fjoin(NEXT_FDIV(r1, Itv.make(yl, -1)), NEXT_FDIV(r1, Itv.make(1, yu)));
        }
        else if (yl == 0 && yu == 0)
        {
            return Itv.bot();
        }
    }
    else if (xl == 0 && xu == 0)
    {
        if (yl > 0) { return Itv.make(yl + 1, INF); }
        else if (yu < 0) { return Itv.make(MINF, yu - 1); }
    }
    else if (xl == -1 && xu == -1)
    {
        if (yl > 0) { return Itv.make(MINF, -yl); }
        else if (yu < 0) { return Itv.make(-yu, INF); }
        else if (0 == yl && yl < yu) { return Itv.make(MINF, -1); }
        else if (yl < yu && yu == 0) { return Itv.make(1, INF); }
        else if (yl == 0 && yu == 0) { return Itv.bot(); }
    }
    else if (xl == 0 && 0 < xu)
    {
        return fjoin(NEXT_FDIV(Itv.make(0, 0), r2), NEXT_FDIV(Itv.make(1, xu), r2));
    }
    else if (xl < -1 && xu == -1)
    {
        return fjoin(NEXT_FDIV(Itv.make(xl, -2), r2), NEXT_FDIV(Itv.make(-1, -1), r2));
    }
    else if (xl <= -1 && xu >= 0)
    {
        Itv r = NEXT_FDIV(Itv.make(-1, -1), r2);
        r.join(NEXT_FDIV(Itv.make(0, 0), r2));
        if (xl != -1) { r.join(NEXT_FDIV(Itv.make(xl, -2), r2)); }
        if (xu != 0) { r.join(NEXT_FDIV(Itv.make(1, xu), r2)); }
        return r;
    }
    return Itv.top();
}

// Lemma C.12 (recursive in the source)
Itv SELF_CDIV(Itv r1, Itv r2)
{
    if (xl - 1 > 0 || xu < 0)
    {
        if (yl > 0)
        {
            return Itv.make(min(cdiv(yl, xu), cdiv(yu, xu)),
                            max(cdiv(yl, xl - 1), cdiv(yu, xl - 1)) - 1);
        }
        else if (yu < 0)
        {
            return Itv.make(min(fdiv(yl, xl - 1), fdiv(yu, xl - 1)) + 1,
                            max(fdiv(yl, xu), fdiv(yu, xu)));
        }
        else if (0 == yl && yl < yu)
        {
            return NEXT_CDIV(r1, Itv.make(1, yu));
        }
        else if (yl < yu && yu == 0)
        {
            return NEXT_CDIV(r1, Itv.make(yl, -1));
        }
        else if (yl < 0 && 0 < yu)
        {
            return fjoin(NEXT_CDIV(r1, Itv.make(yl, -1)), NEXT_CDIV(r1, Itv.make(1, yu)));
        }
        else if (yl == 0 && yu == 0)
        {
            return Itv.bot();
        }
    }
    else if (xl == 0 && xu == 0)
    {
        if (yl > 0) { return Itv.make(MINF, -yl - 1); }
        else if (yu < 0) { return Itv.make(-yu + 1, INF); }
    }
    else if (xl == 1 && xu == 1)
    {
        if (yl > 0) { return Itv.make(yl, INF); }
        else if (yu < 0) { return Itv.make(MINF, yu); }
        else if (0 == yl && yl < yu) { return Itv.make(1, INF); }
        else if (yl < yu && yu == 0) { return Itv.make(MINF, -1); }
        else if (yl == 0 && yu == 0) { return Itv.bot(); }
    }
    else if (xl < 0 && xu == 0)
    {
        return fjoin(NEXT_CDIV(Itv.make(xl, -1), r2), NEXT_CDIV(Itv.make(0, 0), r2));
    }
    else if (xl == 1 && 1 < xu)
    {
        return fjoin(NEXT_CDIV(Itv.make(1, 1), r2), NEXT_CDIV(Itv.make(2, xu), r2));
    }
    else if (xl <= 0 && xu >= 1)
    {
        Itv r = NEXT_CDIV(Itv.make(1, 1), r2);
        r.join(NEXT_CDIV(Itv.make(0, 0), r2));
        if (xl != 0) { r.join(NEXT_CDIV(Itv.make(xl, -1), r2)); }
        if (xu != 1) { r.join(NEXT_CDIV(Itv.make(2, xu), r2)); }
        return r;
    }
    return Itv.top();
}

// Lemma C.13

# Bonsai 2 as the stage-1 judge: zero-shot probe, 2026-11-04

Question: can the resident Bonsai 2 Heretic v2 (ternary, vision tower) judge image-edit pairs well
enough to replace EditScore-7B in the stage-1 rotation, before any training?

Apparatus: `bonsai2-27b` on the Windows desk's NInfer service (RTX 4090, 17.3 GB resident, 30.4 B
params, 9.5 GB artifact, `modalities.vision: true`), reached on the desk at 127.0.0.1:8080.
Pairs: `chibifire/editreward-bench`, shards 2, 3, 7, `dimension = overall`, 8 pairs per task type
across six types (extract, material_alter, motion_change, ps_human, text_change, tone_transfer),
chosen by hash with seed 20261104 (`manifest.json`); `output_images[0]` is the human-preferred edit.
Prompt (`judge.py`): instruction, then source, edit A, edit B as images, one letter at
temperature 0, thinking off, 4 max tokens. Every pair is asked in both orders.

Result (`results.jsonl`):

| measure | value |
| --- | --- |
| accuracy, 48 pairs x 2 orders | **89 / 96 = 0.927** |
| per task | extract 1.00, motion_change 1.00, tone_transfer 1.00, ps_human 0.875, text_change 0.875, material_alter 0.8125 |
| same letter in both orders (position bias) | 5 / 48 pairs |
| wall per judgement | 0.3-1.0 s |

Controls (`controls.py`, same 48 pairs):

| control | expected | measured |
| --- | --- | --- |
| no images, text only | about 0.5 | **0.500** |
| source vs preferred edit (the edit must win) | high | **0.948** |
| source vs source (no right answer), 6 asks | mixed | A A A A A B (an A lean when nothing differs) |

Reading: the images are read (blind drops to chance), the preferred edit is recognised against the
untouched source, and the pairwise accuracy is above the text-only decider baseline of 291/350 =
0.831 (fact of 2026-10-12, different sample). Both orders are counted, so the A lean costs the
score rather than inflating it.

Not measured: the other five task types (background, style, color_alter, subject_add,
subject_remove, subject_replace were not in the three shards fetched); the 350-pair stratified
sample the baseline used; agreement with EditScore-7B's 0-25 scores on the same pairs. n = 48
pairs is a probe, not a shipping number; the shipping gate is the full bench.

Verdict: zero-shot Bonsai 2 is a usable stage-1 judge at 0.93 on this sample, so the training on
`hf:chibifire` starts from above the baseline rather than below it, and EditScore-7B's
`:retiring` row stands.

## Addendum, same day: Bonsai 2 in EditScore's shape

Question: can Bonsai 2 return EditScore's output, `{PF, SC, PQ, overall}` on 0-25 for one
`(source, edited, instruction)`, so callers written against EditScore keep working?

Apparatus: `score.py`, same 48 pairs and server. One edit per call, a three-axis rubric, JSON out
at temperature 0, 40 max tokens; `overall` is the geometric mean of the three axes scaled to 25,
so a zero on any axis zeroes it, as in EditScore. Both edits of each pair are scored separately and
the human-preferred edit must come out higher (`score_results.jsonl`).

| measure | value |
| --- | --- |
| preferred edit scores higher | 35 / 48 pairs; 8 ties; 5 losses |
| win rate, ties excluded | **0.875** (35 / 40) |
| per task (wins / 8) | motion_change 8, text_change 8, material_alter 6, tone_transfer 5, extract 4, ps_human 4 |
| parse failures | 0 / 96 |
| control: source scored as its own edit (n = 8) | PF 3.1, SC 25.0, overall 3.1 (EditScore's smoke test wants PF near 0: pass) |

Reading: the absolute shape works (zero parse failures, the source control behaves, SC saturates
at 25 for an unchanged image as it should), but ranking by independent scores is weaker than the
pairwise question: 0.875 excluding ties against 0.927 pairwise, and 8 of 48 pairs tie because the
scale quantises (23.99 recurs: 25, 24, 23 is the model's "good edit" vowel). The failures cluster in
extract and ps_human, where the two edits are close and a 0-25 rubric cannot separate them; the
pairwise form sees both at once and can.

Rule (operator, 2026-11-04): when the input carries a pair, the judge asks the pair (`judge.py`,
one letter); the EditScore shape (`score.py`) is for a lone `(source, edited, instruction)` only.
The two are the existing shapes; no third form. Both run on the resident model; EditScore-7B is
not needed for either.

# Bonsai 2 in EditScore's shape: one (source, edited, instruction) in, {PF, SC, PQ, overall} out on
# 0-25, overall = geometric-style multiplicative aggregate as EditScore does (a zero on any axis
# zeroes overall). Scores both edits of every pair separately; the check is whether the
# human-preferred edit's overall is higher. Runs on the desk against the local NInfer server.
#   python score.py <dir>   -> score_results.jsonl + tally
import base64, json, re, sys, time, urllib.request
D = sys.argv[1]
KEY = open(r"C:\ProgramData\NInfer\api-key.txt").read().strip()
URL = "http://127.0.0.1:8080/v1/chat/completions"
def img(p): return {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()}}
RUBRIC = ("You are an image-edit scorer. The first image is the original, the second is the edited result. The edit instruction was:\n{instr}\n\n"
          "Score three axes from 0 to 25, integers only.\n"
          "PF, prompt following: 25 if the instruction is fully carried out, 0 if nothing of it is done.\n"
          "SC, source consistency: 25 if everything the instruction did not mention is unchanged, 0 if the image is unrelated to the original.\n"
          "PQ, perceptual quality: 25 for a clean, artefact-free image, 0 for a broken one.\n"
          "Answer with exactly this JSON and nothing else: {{\"PF\": n, \"SC\": n, \"PQ\": n}}")
def score(instr, src, edit):
    body = {"model": "bonsai2-27b", "temperature": 0, "max_tokens": 40,
            "messages": [{"role": "user", "content": [{"type": "text", "text": RUBRIC.format(instr=instr)}, img(src), img(edit)]}],
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
    with urllib.request.urlopen(req, timeout=300) as r: out = json.load(r)
    txt = out["choices"][0]["message"]["content"]
    m = re.search(r'"PF"\s*:\s*(\d+).*?"SC"\s*:\s*(\d+).*?"PQ"\s*:\s*(\d+)', txt, re.S)
    if not m: return None, txt
    pf, sc, pq = (min(25, int(x)) for x in m.groups())
    overall = round(25 * ((pf / 25) * (sc / 25) * (pq / 25)) ** (1 / 3), 2)   # EditScore's multiplicative aggregate, geometric mean
    return {"PF": pf, "SC": sc, "PQ": pq, "overall": overall}, txt
rows = json.load(open(D + "/manifest.json"))
res = open(D + "/score_results.jsonl", "w")
wins = ties = losses = parse_fail = 0; per = {}
src_scores = []
for r in rows:
    rid = r["rid"]; src = f"{D}/img/{rid}_src.png"
    sa, ta = score(r["instruction"], src, f"{D}/img/{rid}_a.png")     # human-preferred
    sb, tb = score(r["instruction"], src, f"{D}/img/{rid}_b.png")
    if sa is None or sb is None:
        parse_fail += 1; res.write(json.dumps({"rid": rid, "parse_fail": True, "raw_a": ta, "raw_b": tb}) + "\n"); continue
    d = sa["overall"] - sb["overall"]
    k = "win" if d > 0 else "tie" if d == 0 else "loss"
    wins += k == "win"; ties += k == "tie"; losses += k == "loss"
    per.setdefault(r["task_type"], [0, 0]); per[r["task_type"]][0] += k == "win"; per[r["task_type"]][1] += 1
    res.write(json.dumps({"rid": rid, "task_type": r["task_type"], "preferred": sa, "other": sb, "result": k}) + "\n"); res.flush()
    print(f"{rid} {r['task_type'][:14]:14} A {sa['overall']:5.2f} ({sa['PF']},{sa['SC']},{sa['PQ']})  B {sb['overall']:5.2f} ({sb['PF']},{sb['SC']},{sb['PQ']})  {k}", flush=True)
# control: the unchanged source as the "edit" must score PF near 0 (EditScore's own smoke test)
for r in rows[:8]:
    s, _ = score(r["instruction"], f"{D}/img/{r['rid']}_src.png", f"{D}/img/{r['rid']}_src.png")
    if s: src_scores.append(s)
n = wins + ties + losses
print(json.dumps({"pairs": n, "preferred_wins": wins, "ties": ties, "losses": losses, "win_rate_excluding_ties": wins / max(1, wins + losses),
                  "per_task_win_rate": {k: v[0] / v[1] for k, v in per.items()}, "parse_fail": parse_fail,
                  "control_source_as_edit": {"mean_PF": sum(s["PF"] for s in src_scores) / len(src_scores), "mean_SC": sum(s["SC"] for s in src_scores) / len(src_scores), "mean_overall": sum(s["overall"] for s in src_scores) / len(src_scores), "n": len(src_scores)}}, indent=1))

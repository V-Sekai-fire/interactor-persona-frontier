# Bonsai 2 as a pairwise image-edit judge, zero-shot, through the vision tower. Runs on the desk
# against the local NInfer server. Reads the API key from the file, never from argv.
#   python judge.py <dir with manifest.json and img/>   -> writes results.jsonl, prints the tally
# Per pair: instruction + source + edit A + edit B, answer one letter at temp 0, reasoning off.
# Controls: every pair is asked twice with A/B swapped (a judge that always says "A" scores 0.5
# across the two orders); and a source-vs-source pair, where no answer is right, must come out
# near 50/50 across orders rather than fixed.
import base64, json, sys, time, urllib.request
D = sys.argv[1]
KEY = open(r"C:\ProgramData\NInfer\api-key.txt").read().strip()
URL = "http://127.0.0.1:8080/v1/chat/completions"
def img(p):
    return {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()}}
def ask(instr, src, a, b):
    content = [
        {"type": "text", "text": "You judge image edits. The instruction was:\n" + instr + "\n\nThe first image is the original. The second is edit A. The third is edit B."},
        img(src), img(a), img(b),
        {"type": "text", "text": "Which edit follows the instruction better while keeping the rest of the original intact? Answer with exactly one letter, A or B."},
    ]
    body = {"model": "bonsai2-27b", "temperature": 0, "max_tokens": 4, "messages": [{"role": "user", "content": content}],
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        out = json.load(r)
    txt = out["choices"][0]["message"]["content"].strip().upper()
    letter = "A" if txt.startswith("A") else "B" if txt.startswith("B") else "?"
    return letter, txt, time.time() - t0
rows = json.load(open(D + "/manifest.json"))
res = open(D + "/results.jsonl", "w")
correct = total = 0; per = {}; same_letter = 0
for r in rows:
    rid = r["rid"]; src = f"{D}/img/{rid}_src.png"; a = f"{D}/img/{rid}_a.png"; b = f"{D}/img/{rid}_b.png"
    l1, t1, s1 = ask(r["instruction"], src, a, b)       # preferred edit is A
    l2, t2, s2 = ask(r["instruction"], src, b, a)       # preferred edit is B
    c1 = l1 == "A"; c2 = l2 == "B"
    correct += c1 + c2; total += 2
    per.setdefault(r["task_type"], [0, 0]); per[r["task_type"]][0] += c1 + c2; per[r["task_type"]][1] += 2
    same_letter += (l1 == l2)
    res.write(json.dumps({"rid": rid, "task_type": r["task_type"], "order1": l1, "order2": l2, "raw1": t1, "raw2": t2, "s": round(s1 + s2, 1)}) + "\n"); res.flush()
    print(f"{rid} {r['task_type'][:14]:14} {l1}{l2} {'ok' if c1 and c2 else '  '} {s1+s2:.1f}s", flush=True)
# source-vs-source control on the first 6 pairs
ctl = []
for r in rows[:6]:
    src = f"{D}/img/{r['rid']}_src.png"
    l, _, _ = ask(r["instruction"], src, src, src); ctl.append(l)
print(json.dumps({"accuracy": correct / total, "n_judgements": total, "pairs": len(rows), "position_bias_same_letter_both_orders": same_letter / len(rows),
                  "per_task": {k: v[0] / v[1] for k, v in per.items()}, "source_vs_source_letters": ctl}, indent=1))

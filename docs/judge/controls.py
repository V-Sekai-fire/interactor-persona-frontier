# Two controls for judge.py's number. (1) blind: the same question with no images; if accuracy
# stays near judge.py's, the images were not read. (2) source-vs-preferred: A is the untouched
# source, B the human-preferred edit (and swapped); the edit must win, so accuracy must be high.
import base64, json, sys, time, urllib.request
D = sys.argv[1]
KEY = open(r"C:\ProgramData\NInfer\api-key.txt").read().strip()
URL = "http://127.0.0.1:8080/v1/chat/completions"
def img(p): return {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()}}
def ask(instr, imgs):
    content = [{"type": "text", "text": "You judge image edits. The instruction was:\n" + instr + "\n\nThe first image is the original. The second is edit A. The third is edit B."}]
    content += imgs
    content.append({"type": "text", "text": "Which edit follows the instruction better while keeping the rest of the original intact? Answer with exactly one letter, A or B."})
    body = {"model": "bonsai2-27b", "temperature": 0, "max_tokens": 4, "messages": [{"role": "user", "content": content}], "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
    with urllib.request.urlopen(req, timeout=300) as r: out = json.load(r)
    t = out["choices"][0]["message"]["content"].strip().upper()
    return "A" if t.startswith("A") else "B" if t.startswith("B") else "?"
rows = json.load(open(D + "/manifest.json"))
blind = 0; svp = 0; n = 0
for r in rows:
    rid = r["rid"]; src = f"{D}/img/{rid}_src.png"; a = f"{D}/img/{rid}_a.png"
    blind += (ask(r["instruction"], []) == "A") + (ask(r["instruction"], []) == "B")   # no images: should be ~0.5
    svp += (ask(r["instruction"], [img(src), img(src), img(a)]) == "B") + (ask(r["instruction"], [img(src), img(a), img(src)]) == "A")
    n += 2
print(json.dumps({"blind_no_images_accuracy": blind / n, "source_vs_preferred_edit_wins": svp / n, "n": n}))

// The challenge's load: virtual users asking for plans, scored by its own thresholds.
// Pass: p95 under 500 ms, p99 under 1 s, under 1 % failed. Ramp until a threshold breaks.
//   k6 run -e HOST=http://<droplet>:9920 -e VUS=1000 deploy/k6.js
import http from "k6/http";
import { check, sleep } from "k6";

const goals = ["world", "prop 7", "garments", "reach-character-10", "runtime", "fly"];

export const options = {
  stages: [
    { duration: "1m", target: Number(__ENV.VUS || 500) },
    { duration: "3m", target: Number(__ENV.VUS || 500) },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_duration: ["p(95)<500", "p(99)<1000"],
    http_req_failed: ["rate<0.01"],
  },
};

export default function () {
  const goal = goals[Math.floor(Math.random() * goals.length)];
  const body = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "message/send",
    params: { message: { role: "user", parts: [{ text: goal }] } } });
  const res = http.post(`${__ENV.HOST || "http://127.0.0.1:9920"}/`, body, { headers: { "Content-Type": "application/json" } });
  check(res, { "200": (r) => r.status === 200, "answer": (r) => r.body.includes('"reached":true') || r.body.includes('"refused"') });
  sleep(10 + Math.random() * 10);  // the video's user: about 0.1 requests per second each
}

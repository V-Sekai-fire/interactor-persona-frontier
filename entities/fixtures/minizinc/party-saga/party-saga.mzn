% Party Saga: a guild party clears a board of tasks. SPDX-License-Identifier: MIT
% Our own model; ideas only from public Challenge families, no code copied. See docs/party-saga.md.
include "globals.mzn";
enum TERRAIN = {LAND, WATER, CLIFF};
enum MODE = {STICK, SPRINT, CLIMB, TELEPORT};
enum RECIPE = {QUICK, PERFORMANCE};
enum ARM = {LEFT, RIGHT, BOTH};
enum ROLE = {TANK, HEALER, DAMAGE, SUPPORT};
enum ELEMENT = {EMBER, TIDE, STONE, GALE};
enum KIND = {SCOUT, DUTY};

int: nn;  set of int: NODE = 1..nn;
int: ne;  set of int: EDGE = 1..ne;
array[EDGE] of NODE: from;  array[EDGE] of NODE: to;
array[EDGE] of int: length;  array[EDGE] of TERRAIN: terrain;
int: nc;  set of int: CHAR = 1..nc;
array[CHAR] of NODE: home;  array[CHAR, MODE] of bool: has_mode;
array[CHAR] of int: arm_reach;  array[CHAR] of int: stride;
array[CHAR] of bool: can_perform;  array[CHAR] of ROLE: role;
array[CHAR] of int: slots;  array[CHAR] of int: cooldown;
int: nk;  set of int: CRYSTAL = 1..nk;  array[CRYSTAL] of ELEMENT: crystal_element;
int: nt;  set of int: TASK = 1..nt;
array[TASK] of KIND: kind;  array[TASK] of NODE: at;  array[TASK] of int: zone;
array[TASK] of bool: required;  array[TASK, RECIPE] of int: duration;
array[TASK] of int: reach_needed;  array[TASK, ROLE] of int: need_role;
array[TASK, ELEMENT] of bool: need_art;
array[TASK] of int: points;  array[TASK] of int: min_points;  array[TASK] of int: bonus;
array[TASK] of int: release;  array[TASK] of int: deadline;
int: nz;  set of int: ZONE = 1..nz;  array[ZONE] of int: zone_capacity;
int: np;  set of int: PAIR = 1..np;  array[PAIR] of TASK: before;  array[PAIR] of TASK: after;
int: climb_min_reach;  int: blink_range;  int: time_weight;  int: point_weight;

int: INF = 1000000;
function int: speed(CHAR: c, MODE: m, TERRAIN: t) =
  if m = STICK then (if t = LAND then stride[c] elseif t = WATER then stride[c] div 2 else 0 endif)
  elseif m = SPRINT then (if t = LAND then (stride[c] * 3) div 2 else 0 endif)
  elseif m = CLIMB then (if t = CLIFF /\ arm_reach[c] >= climb_min_reach then stride[c] div 3 else 0 endif)
  else 0 endif;
function int: ramp(MODE: m) = if m = STICK then 1 elseif m = SPRINT then 2 elseif m = CLIMB then 1 else 0 endif;
function int: mode_time(CHAR: c, MODE: m, EDGE: e) =
  if not has_mode[c, m] then INF
  elseif m = TELEPORT then (if length[e] <= blink_range then 1 else INF endif)
  elseif speed(c, m, terrain[e]) <= 0 then INF
  else (length[e] * 100 + speed(c, m, terrain[e]) - 1) div speed(c, m, terrain[e]) + ramp(m) endif;
array[CHAR, EDGE] of int: edge_time = array2d(CHAR, EDGE, [min([mode_time(c, m, e) | m in MODE]) | c in CHAR, e in EDGE]);
function array[NODE, NODE] of int: fw_step(array[NODE, NODE] of int: d, NODE: k) =
  array2d(NODE, NODE, [min(d[u, v], d[u, k] + d[k, v]) | u, v in NODE]);
function array[NODE, NODE] of int: fw(array[NODE, NODE] of int: d, int: k) =
  if k > nn then d else fw(fw_step(d, k), k + 1) endif;
function array[NODE, NODE] of int: direct(CHAR: c) =
  array2d(NODE, NODE, [if u = v then 0 else min([edge_time[c, e] | e in EDGE where from[e] = u /\ to[e] = v] ++ [INF]) endif | u, v in NODE]);
array[CHAR, NODE, NODE] of int: dist = array3d(CHAR, NODE, NODE, [x | c in CHAR, x in array1d(fw(direct(c), 1))]);

int: maxd = max([dist[c, u, v] | c in CHAR, u, v in NODE where dist[c, u, v] < INF] ++ [0]);
int: maxdur = sum([max(duration[t, QUICK], duration[t, PERFORMANCE]) | t in TASK]);
int: H = maxdur + (nt + 1) * (maxd + max(cooldown ++ [0])) + max(release ++ [0]);

array[TASK] of var bool: done;
array[CHAR, TASK] of var bool: part;
array[TASK] of var RECIPE: how;
array[TASK] of var ARM: arm;
array[TASK] of var 0..H: start;
array[CRYSTAL] of var 0..nc: held;
var 0..H: endtime;

array[0..nc, TASK] of var bool: inparty = array2d(0..nc, TASK, [false | t in TASK] ++ [part[c, t] | c in CHAR, t in TASK]);
array[TASK] of var int: dur = [if kind[t] = DUTY then duration[t, QUICK] else duration[t, how[t]] endif | t in TASK];
array[TASK] of var int: usage = [if kind[t] = DUTY then 2 * sum(c in CHAR)(bool2int(part[c, t])) elseif how[t] = PERFORMANCE then 2 else 1 endif | t in TASK];

constraint forall(t in TASK)(required[t] -> done[t]);
constraint forall(t in TASK)(not done[t] -> (start[t] = 0 /\ how[t] = QUICK /\ forall(c in CHAR)(not part[c, t])));
constraint forall(t in TASK where kind[t] = SCOUT)(done[t] -> sum(c in CHAR)(bool2int(part[c, t])) = 1);
constraint forall(t in TASK where kind[t] = SCOUT)((how[t] = PERFORMANCE <-> arm[t] = BOTH) \/ not done[t]);
constraint forall(t in TASK where kind[t] = DUTY)(how[t] = QUICK /\ arm[t] = BOTH);
constraint forall(t in TASK where kind[t] = DUTY, r in ROLE)(sum(c in CHAR where role[c] = r)(bool2int(part[c, t])) = if done[t] then need_role[t, r] else 0 endif);
constraint forall(t in TASK where kind[t] = SCOUT)(forall(r in ROLE)(need_role[t, r] = 0));
constraint forall(c in CHAR, t in TASK)(part[c, t] -> (dist[c, home[c], at[t]] < INF /\ start[t] >= dist[c, home[c], at[t]] /\ reach_needed[t] <= arm_reach[c]));
constraint forall(c in CHAR, t in TASK where kind[t] = SCOUT)(part[c, t] /\ how[t] = PERFORMANCE -> can_perform[c]);
constraint forall(c in CHAR, t in TASK)(part[c, t] -> start[t] >= release[t] /\ start[t] + dur[t] <= deadline[t]);
constraint forall(c in CHAR, t1, t2 in TASK where t1 < t2)(
  part[c, t1] /\ part[c, t2] ->
    (start[t2] >= start[t1] + dur[t1] + dist[c, at[t1], at[t2]] + (if kind[t1] = DUTY /\ kind[t2] = DUTY then cooldown[c] else 0 endif)
     \/ start[t1] >= start[t2] + dur[t2] + dist[c, at[t2], at[t1]] + (if kind[t1] = DUTY /\ kind[t2] = DUTY then cooldown[c] else 0 endif)
     \/ (kind[t1] = SCOUT /\ kind[t2] = SCOUT /\ at[t1] = at[t2] /\ how[t1] = QUICK /\ how[t2] = QUICK /\ arm[t1] != arm[t2])));
constraint forall(z in ZONE)(cumulative([start[t] | t in TASK where zone[t] = z], [if done[t] then dur[t] else 0 endif | t in TASK where zone[t] = z], [usage[t] | t in TASK where zone[t] = z], zone_capacity[z]));
constraint forall(c in CHAR)(sum(k in CRYSTAL)(bool2int(held[k] = c)) <= slots[c]);
constraint forall(t in TASK where kind[t] = DUTY, e in ELEMENT where need_art[t, e])(done[t] -> exists(k in CRYSTAL)(crystal_element[k] = e /\ held[k] > 0 /\ inparty[held[k], t]));
constraint forall(t in TASK where min_points[t] > 0)(done[t] -> sum(u in TASK where u != t)(points[u] * bool2int(done[u] /\ start[u] + dur[u] <= start[t])) >= min_points[t]);
constraint forall(p in PAIR)(done[after[p]] -> (done[before[p]] /\ start[after[p]] >= start[before[p]] + dur[before[p]]));
constraint forall(t in TASK)(done[t] -> endtime >= start[t] + dur[t]);

var int: bonus_total = sum(t in TASK)(bonus[t] * bool2int(done[t] /\ (kind[t] = DUTY \/ how[t] = PERFORMANCE)));
var int: points_total = sum(t in TASK)(points[t] * bool2int(done[t]));
var int: objective = time_weight * endtime - bonus_total - point_weight * points_total;
solve :: int_search(start, smallest, indomain_min) minimize objective;

output ["objective = ", show(objective), ";\nendtime = ", show(endtime), ";\ndone = ", show(done),
        ";\nparty = ", show([sum(c in CHAR)(if fix(part[c, t]) then pow(2, c - 1) else 0 endif) | t in TASK]),
        ";\ndur = ", show([fix(dur[t]) | t in TASK]), ";\ndist = ", show(array1d(dist)),
        ";\nhow = ", show(how), ";\narm = ", show(arm), ";\nstart = ", show(start), ";\nheld = ", show(held), ";\n"];

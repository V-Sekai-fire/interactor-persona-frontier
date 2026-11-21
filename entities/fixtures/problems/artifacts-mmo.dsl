# A goal, what holds at the start, and the plan the planner must give (expect refused when it must find none).
domain artifacts_mmo

problem fight-far
  goal fight-at(c1, chickens)
  init hp_full(c1) = 1
  expect move(c1, chickens), fight(c1, chickens)

problem fight-there
  goal fight-at(c1, chickens)
  init at(c1) = chickens
  init hp_full(c1) = 1
  expect fight(c1, chickens)

problem gather-ok
  goal gather-at(c1, copper_rocks, mining, 1, copper_ore, 1)
  init skill(c1, mining) = 1
  expect move(c1, copper_rocks), gather(c1, copper_rocks, mining, 1, copper_ore, 1)

problem gather-low
  goal gather-at(c1, copper_rocks, mining, 5, copper_ore, 1)
  init skill(c1, mining) = 1
  expect refused

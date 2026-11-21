# A goal, what holds at the start, and the plan the planner must give (expect refused when it must find none).
domain artifacts_mmo

problem fight-far
  goal fight-at(c1, chicken_0_1)
  init hp_full(c1) = 1
  expect move(c1, chicken_0_1), fight(c1, chicken_0_1)

problem fight-there
  goal fight-at(c1, chicken_0_1)
  init at(c1) = chicken_0_1
  init hp_full(c1) = 1
  expect fight(c1, chicken_0_1)

problem gather-ok
  goal gather-at(c1, copper_rocks_2_0, mining, 1, copper_ore, 1)
  init skill(c1, mining) = 1
  expect move(c1, copper_rocks_2_0), gather(c1, copper_rocks_2_0, mining, 1, copper_ore, 1)

problem gather-low
  goal gather-at(c1, copper_rocks_2_0, mining, 5, copper_ore, 1)
  init skill(c1, mining) = 1
  expect refused

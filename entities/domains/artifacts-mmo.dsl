# The primitives of an API-first MMO as a planner domain. One action per operation the player may act with: an action says which
# operation it calls, what that operation needs before it runs (need) and what it leaves behind (set). The planner computes on
# integers; the names below are enum members it resolves, and a fact is set to a value, never counted, so an action that makes
# items says the count it claims to leave (after) and the runtime checks that claim against the real inventory.
domain artifacts_mmo
version 0.1.0
description Primitives of an API-first MMO, one action per operation the player may act with. Durations are unmeasured until experience reports replace them.
default takes 5s unmeasured

enum char: c1=1 c2=2 c3=3 c4=4 c5=5
enum skill: alchemy cooking fishing gearcrafting jewelrycrafting mining weaponcrafting woodcutting
enum slot: weapon shield helmet body_armor leg_armor boots ring1 ring2 amulet artifact1 artifact2 artifact3 utility1 utility2 bag rune

fact at(c: char) holds tile                # the tile the character stands on
fact hp_full(c: char)                      # 1 when hit points are full
fact inv_full(c: char)                     # 1 when the inventory is full
fact task(c: char)                         # 1 when a task is held
fact skill(c: char, skill: skill)          # the skill level
fact slot_full(c: char, slot: slot)        # 1 when the slot holds an item
fact equipped(c: char, slot: slot) holds item
fact have(c: char, item: item)             # the count held, as claimed by the action that last changed it

action move(c: char, to: tile)  calls action_move
  set at(c) = to

action fight(c: char, place: tile)  calls action_fight
  need at(c) = place
  need inv_full(c) = 0
  set hp_full(c) = 0

action rest(c: char)  calls action_rest
  set hp_full(c) = 1

action gather(c: char, place: tile, skill: skill, level, item: item, after)  calls action_gathering
  need at(c) = place
  need skill(c, skill) >= level
  need inv_full(c) = 0
  set have(c, item) = after

action craft(c: char, place: tile, skill: skill, level, item: item, quantity, after)  calls action_crafting
  need at(c) = place
  need skill(c, skill) >= level
  need inv_full(c) = 0
  set have(c, item) = after

action recycle(c: char, place: tile, skill: skill, level, item: item, quantity)  calls action_recycling
  need at(c) = place
  need skill(c, skill) >= level
  need inv_full(c) = 0

action equip(c: char, item: item, slot: slot)  calls action_equip
  need slot_full(c, slot) = 0
  set slot_full(c, slot) = 1
  set equipped(c, slot) = item

action unequip(c: char, slot: slot)  calls action_unequip
  need slot_full(c, slot) = 1
  set slot_full(c, slot) = 0

action use(c: char, item: item, quantity)  calls action_use

action deposit-item(c: char, place: tile, item: item, quantity)  calls action_bank_deposit_item
  need at(c) = place
  set inv_full(c) = 0

action deposit-gold(c: char, place: tile, quantity)  calls action_bank_deposit_gold
  need at(c) = place

action withdraw-item(c: char, place: tile, item: item, quantity, after)  calls action_bank_withdraw_item
  need at(c) = place
  need inv_full(c) = 0
  set have(c, item) = after

action withdraw-gold(c: char, place: tile, quantity)  calls action_bank_withdraw_gold
  need at(c) = place

action buy(c: char, place: tile, item: item, quantity, after)  calls action_npc_buy
  need at(c) = place
  need inv_full(c) = 0
  set have(c, item) = after

action sell(c: char, place: tile, item: item, quantity)  calls action_npc_sell
  need at(c) = place

action new-task(c: char, place: tile)  calls action_task_new
  need at(c) = place
  need task(c) = 0
  set task(c) = 1

action complete-task(c: char, place: tile)  calls action_task_complete
  need at(c) = place
  need task(c) >= 1
  set task(c) = 0

action cancel-task(c: char, place: tile)  calls action_task_cancel
  need at(c) = place
  need task(c) >= 1
  set task(c) = 0

method go-to(c: char, place: tile)
  there: when at(c) = place
  move: -> move(c, place)

method heal(c: char)
  full: when hp_full(c) = 1
  rest: -> rest(c)

# each of these actions also gets a method <action>-at: go to the place, then act
at-place fight gather craft recycle deposit-item deposit-gold withdraw-item withdraw-gold buy sell new-task complete-task cancel-task

-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Turbo.Solve

/-! The cooperative GPU form of `Turbo.Solve`: one workgroup of 256 threads is one block of the source (`barebones_dive_and_solve.hpp`), as in Turbo's own kernel.
    All threads share the work of one node (the fixpoint sweep over the bytecodes, the scan for an unentailed propagator, the variable selection, the store copies);
    thread 0 runs the serial search logic. Control flow is uniform across the group: every value a branch reads was written before a barrier.
    The store is changed with `InterlockedMax` on lower bounds and `InterlockedMin` on upper bounds, which is the meet and is safe when threads race. -/
namespace Turbo
open LeanSlang

def sNewBest := 20
def sFound := 21
/-- State slot 28: how many entries of the block's list of changed variables are valid. State slot 29: when non-zero, the next launch treats every variable as changed (a loaded checkpoint does not carry the lists). -/
def sDirtyN := 28
def sResync := 29
/-- State slot 33: parity of the list of changed variables being filled; slots 28 and 32 count the entries of list 0 and list 1. -/
def sDirtyPar := 33
def lanes : E := n 256
def tidE : E := v "tid"
def sync : S := .expr (call "AllMemoryBarrierWithGroupSync" [])
def leader (body : List S) : S := when (eq tidE (n 0)) body
/-- The device clock, truncated to 32 bits (a difference of two readings is right while it stays under 2^32 ticks). -/
def clockNow : E := call "int" [call "getRealtimeClockLow" []]
/-- Profile slots of the per-block state: 24 start of the timed region, 25 ticks (in sixteenths) spent in propagation during this launch, 26 ticks of the whole launch, 27 start of the launch. -/
def profStart : S := leader [setState 24 clockNow]
def profEnd : S := leader [setState 25 (add (stateAt 25) (bin ">>" (bin "-" clockNow (stateAt 24)) (n 4)))]
def shared (name : String) : E := v name
/-- `for (i = tid + start; i < bound; i += 256) body`, in its own scope. -/
def strided (i : String) (start bound : E) (body : List S) : S :=
  .ifThen (.litBool true)
    [.declInit int i (add start tidE), .whileLoop (lt (v i) bound) (body ++ [.assign (v i) (add (v i) lanes)])] []

def dirtyFlagAt (x : E) : E := .index (v "dirty_flag") (add blockBase x)
/-- The block keeps two lists of changed variables and alternates between them: one holds the variables found changed and not yet used, the other is being filled while the first is used. `par` is the parity of the list being filled. -/
def dirtyListAt (par i : E) : E := .index (v "dirty_list") (add (mul (mul (v "b") (n 2)) vars) (add (mul par vars) i))
def dirtyCountAt (par : E) : E := .index (v "state") (add (mul (v "b") (n 36)) (add (n sDirtyN) (mul par (n 4))))
def propMarkAt (p : E) : E := .index (v "prop_mark") (add (mul (v "b") (ctl cBytecodes)) p)
def workListAt (i : E) : E := .index (v "work_list") (add (mul (v "b") (ctl cBytecodes)) i)
def bigListAt (i : E) : E := .index (v "big_list") (add blockBase i)
def bigDegree : Nat := 48
def queueCount : E := .index (v "s_nw") (v "ph")
def bigCount : E := .index (v "s_nbig") (v "ph")
/-- Queue propagator `p` for this round unless it already is: the mark is set by the first thread to ask. -/
def queueProp (p : E) : List S :=
  [.declInit int "q_prop" p, .declInit int "was_marked" (n 0),
   .expr (call "InterlockedExchange" [propMarkAt (v "q_prop"), n 1, v "was_marked"]),
   when (eq (v "was_marked") (n 0))
     [.declInit int "work_slot" (n 0), .expr (call "InterlockedAdd" [queueCount, n 1, v "work_slot"]), .assign (workListAt (v "work_slot")) (v "q_prop")]]
/-- A variable changed: put it on the list being filled once (the flag says whether it is on a list already). -/
def markDirty (x : E) : List S :=
  [.declInit int "was_dirty" (n 0), .expr (call "InterlockedExchange" [dirtyFlagAt x, n 1, v "was_dirty"]),
   when (eq (v "was_dirty") (n 0))
     [.declInit int "fill_par" (stateAt sDirtyPar), .declInit int "dirty_slot" (n 0),
      .expr (call "InterlockedAdd" [dirtyCountAt (v "fill_par"), n 1, v "dirty_slot"]), .assign (dirtyListAt (v "fill_par") (v "dirty_slot")) x]]
/-- Every variable changed: after a subproblem root is loaded, or a checkpoint. All threads. -/
def markAllDirty : List S :=
  [.declInit int "all_par" (stateAt sDirtyPar),
   strided "k" (n 0) vars [.assign (dirtyFlagAt (v "k")) (n 1), .assign (dirtyListAt (v "all_par") (v "k")) (v "k")],
   sync,
   leader [.assign (dirtyCountAt (v "all_par")) vars],
   sync]

def embedA : SlangFunctionDecl :=
  { retType := bool, name := "embed_a", params := [param "b" int, param "x" int, param "r" itv],
    body := [
      .declInit int "current_lower" (cell "lower" (v "x")), .declInit int "current_upper" (cell "upper" (v "x")),
      .declInit bool "tighter_lower" (gt (lower (v "r")) (v "current_lower")), .declInit bool "tighter_upper" (lt (upper (v "r")) (v "current_upper")),
      when (land (.un "!" (v "tighter_lower")) (.un "!" (v "tighter_upper"))) [ret (.litBool false)],
      .declInit int "old_lower" (v "current_lower"), .declInit int "old_upper" (v "current_upper"),
      when (v "tighter_lower") [.expr (call "InterlockedMax" [cell "lower" (v "x"), lower (v "r"), v "old_lower"])],
      when (v "tighter_upper") [.expr (call "InterlockedMin" [cell "upper" (v "x"), upper (v "r"), v "old_upper"])],
      .declInit int "new_lower" (mx (v "old_lower") (lower (v "r"))), .declInit int "new_upper" (mn (v "old_upper") (upper (v "r"))),
      .declInit bool "changed" (lor (ne (v "new_lower") (v "old_lower")) (ne (v "new_upper") (v "old_upper"))),
      when (land (v "changed") (call "itv_is_bot" [mk (v "new_lower") (v "new_upper")])) [setState sBot (n 1)],
      when (v "changed") (markDirty (v "x")),
      ret (v "changed")] }

def deduceBytecodeA : SlangFunctionDecl :=
  { retType := bool, name := "deduce_bytecode_a", params := [param "b" int, param "i" (.scalar .uint)],
    body := codeFields ++ [
      .expr (call "deduce" [.member (v "c") "x", v "r1", v "r2", v "r3"]),
      .declInit bool "changed" (call "embed_a" [v "b", v "x", v "r1"]),
      .assign (v "changed") (lor (call "embed_a" [v "b", v "y", v "r2"]) (v "changed")),
      .assign (v "changed") (lor (call "embed_a" [v "b", v "z", v "r3"]) (v "changed")),
      ret (v "changed")] }

def copyCoop (fromLower fromUpper toLower toUpper : String) (fromBase toBase : E) : S :=
  strided "k" (n 0) vars
    [.assign (.index (v toLower) (add toBase (v "k"))) (.index (v fromLower) (add fromBase (v "k"))),
     .assign (.index (v toUpper) (add toBase (v "k"))) (.index (v fromUpper) (add fromBase (v "k")))]

def params2 : List SlangBinding := [param "b" int, param "tid" int]

/-- `propagate`: fixpoint by all threads, then the solution test; the leader updates the statistics and the best bound, all threads copy a new best store. -/
def propagateCoop : SlangFunctionDecl :=
  { name := "propagate_coop", params := params2,
    body := [
      leader [setState sLeaf (n 0), .assign (.index (v "s_nw") (n 0)) (n 0), .assign (.index (v "s_nw") (n 1)) (n 0), .assign (.index (v "s_nbig") (n 0)) (n 0), .assign (.index (v "s_nbig") (n 1)) (n 0)],
      sync,
      .declInit int "cur" (stateAt sDirtyPar),
      .declInit int "ph" (n 0),
      .declInit int "again" (pick (ne (dirtyCountAt (v "cur")) (n 0)) (n 1) (n 0)),
      .whileLoop (ne (v "again") (n 0))
        [.declInit int "dirty_count" (dirtyCountAt (v "cur")),
         -- the other list is filled from now on; the counters of the other parity are the ones this round does not use
         leader [setState 24 clockNow, setState sDirtyPar (sub (n 1) (v "cur")), .assign (.index (v "s_nw") (sub (n 1) (v "ph"))) (n 0), .assign (.index (v "s_nbig") (sub (n 1) (v "ph"))) (n 0)],
         -- the propagators of every changed variable, each once: a variable with few watchers is walked by one thread, one with many by the whole block
         strided "i" (n 0) (v "dirty_count")
           [.declInit int "x" (dirtyListAt (v "cur") (v "i")),
            .assign (dirtyFlagAt (v "x")) (n 0),
            .declInit int "k" (.index (v "var_start") (v "x")),
            .declInit int "stop" (.index (v "var_start") (add (v "x") (n 1))),
            .ifThen (gt (sub (v "stop") (v "k")) (n bigDegree))
              [.declInit int "big_slot" (n 0), .expr (call "InterlockedAdd" [bigCount, n 1, v "big_slot"]), .assign (bigListAt (v "big_slot")) (v "x")]
              [.whileLoop (lt (v "k") (v "stop")) (queueProp (.index (v "var_props") (v "k")) ++ [.assign (v "k") (add (v "k") (n 1))])]],
         sync,
         .declInit int "big_count" bigCount,
         .ifThen (ne (v "big_count") (n 0))
           [.declInit int "bj" (n 0),
            .whileLoop (lt (v "bj") (v "big_count"))
              [.declInit int "bx" (bigListAt (v "bj")),
               strided "bk" (.index (v "var_start") (v "bx")) (.index (v "var_start") (add (v "bx") (n 1))) (queueProp (.index (v "var_props") (v "bk"))),
               .assign (v "bj") (add (v "bj") (n 1))],
            sync] [],
         .declInit int "work_count" queueCount,
         leader [setState 34 (add (stateAt 34) (bin ">>" (bin "-" clockNow (stateAt 24)) (n 4))), setState 24 clockNow, .assign (dirtyCountAt (v "cur")) (n 0), setState 30 (add (stateAt 30) (v "work_count")), setState 31 (add (stateAt 31) (n 1))],
         strided "j" (n 0) (v "work_count")
           [.declInit int "q" (workListAt (v "j")),
            .assign (propMarkAt (v "q")) (n 0),
            .expr (call "deduce_bytecode_a" [v "b", uintOf (v "q")])],
         sync,
         leader [setState 35 (add (stateAt 35) (bin ">>" (bin "-" clockNow (stateAt 24)) (n 4)))],
         .assign (v "cur") (sub (n 1) (v "cur")),
         .assign (v "ph") (sub (n 1) (v "ph")),
         .assign (v "again") (pick (land (ne (dirtyCountAt (v "cur")) (n 0)) (eq (stateAt sBot) (n 0))) (n 1) (n 0))],
      -- a failure leaves changed variables on the list: clear them, the store is restored before the next propagation
      .ifThen (ne (dirtyCountAt (v "cur")) (n 0))
        [.declInit int "left_over" (dirtyCountAt (v "cur")),
         strided "i" (n 0) (v "left_over") [.assign (dirtyFlagAt (dirtyListAt (v "cur") (v "i"))) (n 0)],
         sync,
         leader [.assign (dirtyCountAt (v "cur")) (n 0)],
         sync] [],
      leader [.assign (shared "s_flag") (n 0)],
      sync,
      when (eq (stateAt sBot) (n 0))
        [strided "i" (n 0) (ctl cBytecodes) [when (land (eq (shared "s_flag") (n 0)) (.un "!" (call "ask_bytecode_b" [v "b", uintOf (v "i")]))) [.assign (shared "s_flag") (n 1)]]],
      sync,
      leader [
        .ifThen (eq (stateAt sBot) (n 0))
          [when (eq (shared "s_flag") (n 0))
            [setState sLeaf (n 1),
             .ifThen (ge (ctl cObjective) (n 0))
               [.declInit int "bound" (cell "lower" (ctl cObjective)),
                when (gt (stateAt sBestBound) (v "bound"))
                  [setState sBestBound (v "bound"), .expr (call "InterlockedMin" [ctl cApproxBest, v "bound"]), setState sNewBest (n 1), bump sSolutions]]
               [setState sNewBest (n 1), bump sSolutions, .assign (ctl cStop) (n 1)]]]
          [setState sLeaf (n 1)],
        bump sNodes,
        setState sFails (add (stateAt sFails) (pick (eq (stateAt sBot) (n 1)) (n 1) (n 0))),
        setState sDepthMax (mx (stateAt sDepthMax) decDepth),
        when (lor (ge (stateAt sNodes) (ctl cStopNodes)) (ne (ctl cStop) (n 0))) [setState sExhaustive (n 0), setState sStop (n 1)]],
      sync,
      when (ne (stateAt sNewBest) (n 0))
        [copyCoop "lower" "upper" "best_lower" "best_upper" blockBase blockBase,
         sync,
         leader [setState sNewBest (n 0)],
         sync]] }

/-- `split` for strategy `s`: the candidates are scanned by all threads with group-shared minima, the leader pushes the decision. -/
def splitStrategyCoop : SlangFunctionDecl :=
  let order := strategyField (v "s") 0
  let lowerAt := cell "lower" (v "var")
  let upperAt := cell "upper" (v "var")
  let keyE : E := pick (eq order (n 1)) (sub upperAt lowerAt)
    (pick (eq order (n 2)) (neg (sub upperAt lowerAt)) (pick (eq order (n 4)) (neg upperAt) lowerAt))
  let scanVar : List S := [.declInit int "var" variableAt]
  let inputOrder : E := lor (eq order (n 0)) (eq order (n 5))
  { name := "split_strategy_coop", params := [param "b" int, param "tid" int, param "s" int],
    body := [
      .declInit int "count" candidateCount,
      leader [.assign (shared "s_idx") (v "count"), .assign (shared "s_key") infinity, .assign (shared "s_have") (n 0), .assign (shared "s_pick") (v "count")],
      sync,
      strided "i" (stateAt sNextVar) (v "count")
        (scanVar ++ [when (branchable lowerAt upperAt)
          [.expr (call "InterlockedMin" [shared "s_idx", v "i"]),
           when (.un "!" inputOrder) [.expr (call "InterlockedMin" [shared "s_key", keyE]), .assign (shared "s_have") (n 1)]]]),
      sync,
      leader [
        .ifThen inputOrder
          [setState sNextVar (shared "s_idx"),
           when (ne (shared "s_idx") (v "count"))
             [.declInit int "var" (pick (eq (strategyField (v "s") 3) (n 0)) (shared "s_idx") (.index (v "strategy_vars") (add (strategyField (v "s") 2) (shared "s_idx")))),
              .expr (call "push_decision" [v "b", strategyField (v "s") 1, v "var"]), setState sFound (n 1)]]
          [when (ne (shared "s_have") (n 0)) [setState sNextVar (shared "s_idx")]]],
      sync,
      when (land (.un "!" inputOrder) (ne (shared "s_have") (n 0)))
        [strided "i" (stateAt sNextVar) (v "count")
          (scanVar ++ [when (land (branchable lowerAt upperAt) (eq keyE (shared "s_key"))) [.expr (call "InterlockedMin" [shared "s_pick", v "i"])]]),
         sync,
         leader [
           .declInit int "var" (pick (eq (strategyField (v "s") 3) (n 0)) (shared "s_pick") (.index (v "strategy_vars") (add (strategyField (v "s") 2) (shared "s_pick")))),
           .expr (call "push_decision" [v "b", strategyField (v "s") 1, v "var"]), setState sFound (n 1)]],
      sync] }

/-- `BlockData::split`: strategies in order until one finds a variable; `state[found]` says whether one did. -/
def splitCoop : SlangFunctionDecl :=
  { name := "split_coop", params := params2,
    body := [
      leader [.declInit int "current_depth" decDepth, setDec decDepth fVar (neg (n 1)), setState sFound (n 0)],
      sync,
      .whileLoop (land (eq (stateAt sFound) (n 0)) (lt (stateAt sStrategy) (ctl cStrategies)))
        [.expr (call "split_strategy_coop" [v "b", tid, stateAt sStrategy]),
         leader [when (eq (stateAt sFound) (n 0)) [bump sStrategy, setState sNextVar (n 0)]],
         sync]] }
  where tid := tidE

def objectiveStepA : List S :=
  [when (ge (ctl cObjective) (n 0))
    [when (ne (ctl cApproxBest) infinity)
      [.expr (call "embed_a" [v "b", ctl cObjective, mk minusInfinity (sub (ctl cApproxBest) (n 1))]),
       .expr (call "embed_a" [v "b", ctl cObjective, mk minusInfinity (sub (stateAt sBestBound) (n 1))])],
     when (eq (ctl cApproxBest) minusInfinity) [setState sStop (n 1), .assign (ctl cStop) (n 1)]]]

/-- Section IV: restore the subproblem root and re-apply the decisions on the path, all threads sharing the re-application. -/
def backtrackCoop : SlangFunctionDecl :=
  { name := "backtrack_coop", params := params2,
    body := [
      leader [setState sDepth (.index (v "decisions")
        (add (mul (add (mul (v "b") (ctl cMaxDepth)) (sub decDepth (n 1))) (n 8)) (add (n fRope0) (decAt (sub decDepth (n 1)) fCurrent)))),
        when (eq decDepth (neg (n 1))) [setState sInner (n 0)]],
      sync,
      when (ne decDepth (neg (n 1)))
        [copyCoop "snap_lower" "snap_upper" "lower" "upper" blockBase blockBase,
         sync,
         leader [setState sBot (n 0)],
         sync,
         .declInit int "again" (n 1),
         .whileLoop (ne (v "again") (n 0))
           [leader [.assign (shared "s_changed") (n 0)],
            sync,
            strided "i" (n 0) (sub decDepth (n 1))
              [when (call "embed_a" [v "b", decVar (v "i"), call "current_child" [v "b", v "i"]]) [.assign (shared "s_changed") (n 1)]],
            sync,
            .assign (v "again") (shared "s_changed"),
            sync],
         leader [.expr (call "embed_a" [v "b", decVar (sub decDepth (n 1)), call "next_child" [v "b", sub decDepth (n 1)]]),
                 setState sStrategy (stateAt sSnapStrategy), setState sNextVar (stateAt sSnapNextVar)],
         sync]] }

/-- One iteration of the search loop of section F. -/
def searchIterationCoop : List S :=
  [.ifThen (land (ne (stateAt sInner) (n 0)) (eq (stateAt sStop) (n 0)))
     ([leader objectiveStepA, sync,
       when (eq (stateAt sStop) (n 0))
         [profStart, .expr (call "propagate_coop" [v "b", tidE]), profEnd,
          when (eq (stateAt sLeaf) (n 0))
            [when (eq decDepth (n 0))
               [copyCoop "lower" "upper" "snap_lower" "snap_upper" blockBase blockBase,
                sync,
                leader [setState sSnapStrategy (stateAt sStrategy), setState sSnapNextVar (stateAt sNextVar)],
                sync],
             .expr (call "split_coop" [v "b", tidE]),
             leader [.ifThen (ne (stateAt sFound) (n 0))
               [.expr (call "embed_a" [v "b", decVar (sub decDepth (n 1)), call "next_child" [v "b", sub decDepth (n 1)]])]
               [setState sLeaf (n 1), setState sExhaustive (n 0)]],
             sync],
          when (eq (stateAt sLeaf) (n 1))
            [.ifThen (eq decDepth (n 0)) [leader [setState sInner (n 0)], sync] [.expr (call "backtrack_coop" [v "b", tidE])]]],
       leader [sliceCheck],
       sync])
     [leader [setState sPhase (n phaseNext)], sync]]

def diveIterationCoop (atomic : Bool) : List S :=
  [.ifThen (land (land (gt (stateAt sRemaining) (n 0)) (eq (stateAt sLeaf) (n 0))) (eq (stateAt sStop) (n 0)))
     [profStart, .expr (call "propagate_coop" [v "b", tidE]), profEnd,
      when (eq (stateAt sLeaf) (n 0))
        [.expr (call "split_coop" [v "b", tidE]),
         leader [.ifThen (ne (stateAt sFound) (n 0))
           [setState sRemaining (sub (stateAt sRemaining) (n 1)), setState sDepth (sub decDepth (n 1)),
            .declInit int "branch" (bin "&" (bin ">>" (stateAt sSubproblem) (stateAt sRemaining)) (n 1)),
            .expr (call "embed_a" [v "b", decVar (n 0), call "child" [v "b", n 0, v "branch"]])]
           [setState sLeaf (n 1), setState sExhaustive (n 0)]],
         sync],
      leader [sliceCheck],
      sync]
     [leader [.ifThen (land (eq (stateAt sLeaf) (n 1)) (eq (stateAt sStop) (n 0)))
        [.declInit int "skip_to" (bin "<<" (add (bin ">>" (stateAt sSubproblem) (stateAt sRemaining)) (n 1)) (stateAt sRemaining)),
         (if atomic then .expr (call "InterlockedMax" [ctl cNextSubproblem, v "skip_to"]) else .assign (ctl cNextSubproblem) (mx (ctl cNextSubproblem) (v "skip_to"))),
         setState sPhase (n phaseNext)]
        [.ifThen (eq (stateAt sStop) (n 0))
           [setState sInner (n 1), setState sPhase (n phaseSearch)]
           [setState sPhase (n phaseDone)]]],
      sync]]

def startSubproblemBody : List S :=
  [copyCoop "root_lower" "root_upper" "lower" "upper" zeroBase blockBase, sync] ++ markAllDirty ++
  [leader [setState sStrategy (n 0), setState sNextVar (n 0), setState sDepth (n 0), setState sBot (n 0),
           setState sRemaining (ctl cPower), setState sLeaf (n 0), setState sPhase (n phaseDive)],
   sync]

def startSubproblemCoop : List S :=
  [.ifThen (ge (stateAt sSubproblem) (v "num_subproblems")) [leader [setState sPhase (n phaseDone)], sync] startSubproblemBody]
def nextSubproblemCoop : List S :=
  [leader (nextSubproblem true), sync]

/-- The entry: one workgroup per block. -/
def solveCoopFn : SlangFunctionDecl :=
  { attrs := [.shaderCompute, .numthreads 256 1 1], name := "solve",
    params := [⟨"gid", .vec .uint 3, .svGroupId, none, none, .qIn⟩, ⟨"gtid", .vec .uint 3, .svGroupThreadId, none, none, .qIn⟩],
    body := [
      .declInit int "b" (call "int" [.member (v "gid") "x"]),
      .declInit int "tid" (call "int" [.member (v "gtid") "x"]),
      when (ge (v "b") (ctl cBlocks)) [.retVoid],
      leader [when (eq (stateAt sPhase) (n 0)) initBlock],
      sync,
      .declInit int "num_subproblems" (bin "<<" (n 1) (ctl cPower)),
      leader [setState sYield (n 0), setState sSliceStart (stateAt sNodes), setState 25 (n 0), setState 26 (n 0), setState 27 clockNow, setState 30 (n 0), setState 31 (n 0), setState 34 (n 0), setState 35 (n 0)],
      sync,
      .ifThen (ne (stateAt sResync) (n 0)) (markAllDirty ++ [leader [setState sResync (n 0)], sync]) [],
      .whileLoop (land (land (ne (stateAt sPhase) (n phaseDone)) (ne (stateAt sPhase) (n phaseAwait))) (eq (stateAt sYield) (n 0)))
        [when (eq (stateAt sPhase) (n phaseStart)) startSubproblemCoop,
         when (eq (stateAt sPhase) (n phaseDive)) (diveIterationCoop true),
         when (eq (stateAt sPhase) (n phaseSearch)) searchIterationCoop,
         when (eq (stateAt sPhase) (n phaseNext)) nextSubproblemCoop],
      sync,
      leader [setState 26 (bin ">>" (bin "-" clockNow (stateAt 27)) (n 4))]] }

/-- Which propagators watch each variable (read only), and per block: the list of changed variables with its flags, the marks of the propagators queued, and the queue. -/
def incrementalBuffers : List SlangBinding :=
  [global "var_start" (.roBuf int) 14, global "var_props" (.roBuf int) 15, global "dirty_flag" (.rwBuf int) 16, global "dirty_list" (.rwBuf int) 17,
   global "prop_mark" (.rwBuf int) 18, global "work_list" (.rwBuf int) 19, global "big_list" (.rwBuf int) 20]

def coopShared : List SlangGroupSharedDecl :=
  (["s_changed", "s_flag", "s_idx", "s_key", "s_have", "s_pick"].map fun name => { name, elemType := int }) ++
  [{ name := "s_nw", elemType := int, dims := [2] }, { name := "s_nbig", elemType := int, dims := [2] }]

def solveCoopModule : SlangShaderModule :=
  { shaderModule with
    globals := globalBuffers ++ incrementalBuffers,
    groupShared := coopShared,
    functions := shaderModule.functions ++
      [embedB, loadB, askBytecodeB, pushDecision, childFn, currentChildFn, nextChildFn,
       embedA, deduceBytecodeA, propagateCoop, splitStrategyCoop, splitCoop, backtrackCoop, solveCoopFn] }

end Turbo

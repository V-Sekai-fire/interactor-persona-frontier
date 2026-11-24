-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2025 Pierre Talbot
-- SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
-- SPDX-License-Identifier: Apache-2.0 AND MIT
import Turbo.Fixpoint

/-! Turbo's `barebones_dive_and_solve.hpp` for one block per workgroup: propagate, split, decisions with ropes, backtracking,
    branch and bound on the objective, and the diving over subproblems. Names follow the source.
    Buffers (all `int`): `lower`/`upper` the stores of the blocks (`blocks * variables`), `root_lower`/`root_upper` the unified root,
    `snap_lower`/`snap_upper` each block's `root_store`, `best_lower`/`best_upper` each block's `best_store`, `code` the bytecodes,
    `strategies` `(variable order, value order, offset, count)` into `strategy_vars`, `decisions` eight ints per depth per block,
    `state` sixteen ints per block, `control` the grid data. -/
namespace Turbo
open LeanSlang

-- control
def cBytecodes := 0
def cVariables := 1
def cStrategies := 2
def cObjective := 3
def cPower := 4
def cMaxDepth := 5
def cBlocks := 6
def cStopNodes := 7
def cEps := 8
def cStop := 9
def cNextSubproblem := 10
def cApproxBest := 11
def cError := 12
def cSliceNodes := 13
def cExternal := 14
def cCancel := 15
-- per-block state
def sDepth := 0
def sStrategy := 1
def sNextVar := 2
def sSnapStrategy := 3
def sSnapNextVar := 4
def sBestBound := 5
def sSolutions := 6
def sNodes := 7
def sFails := 8
def sSubproblem := 9
def sExhaustive := 10
def sDepthMax := 11
def sBot := 12
def sLeaf := 13
def sStop := 14
def sRemaining := 15
def sPhase := 16
def sInner := 17
def sYield := 18
def sSliceStart := 19
-- phases of the block loop; 0 is a block that has not started
def phaseStart := 1
def phaseDive := 2
def phaseSearch := 3
def phaseNext := 4
def phaseDone := 5
def phaseAwait := 6

def ctl (k : Nat) : E := .index (v "control") (.litUint k)
def stateAt (k : Nat) : E := .index (v "state") (add (mul (v "b") (n 32)) (n k))
def setState (k : Nat) (e : E) : S := .assign (stateAt k) e
def bump (k : Nat) : S := setState k (add (stateAt k) (n 1))
def vars : E := ctl cVariables
def cell (name : String) (x : E) : E := .index (v name) (add (mul (v "b") vars) x)
def decAt (depth : E) (field : Nat) : E :=
  .index (v "decisions") (add (mul (add (mul (v "b") (ctl cMaxDepth)) depth) (n 8)) (n field))
def setDec (depth : E) (field : Nat) (e : E) : S := .assign (decAt depth field) e
def fVar := 0
def fCurrent := 1
def fChild0Lower := 2
def fChild0Upper := 3
def fChild1Lower := 4
def fChild1Upper := 5
def fRope0 := 6
def fRope1 := 7
def decDepth : E := stateAt sDepth
def uintOf (e : E) : E := call "uint" [e]
def loopOver (name : String) (bound : E) (body : List S) : S := .forCount name (.litUint 0) (uintOf bound) body

def embedB : SlangFunctionDecl :=
  { retType := bool, name := "embed_b", params := [param "b" int, param "x" int, param "r" itv],
    body := [
      .declInit itv "s" (mk (cell "lower" (v "x")) (cell "upper" (v "x"))),
      .declInit bool "changed" (call "itv_meet" [v "s", v "r"]),
      .assign (cell "lower" (v "x")) (lower (v "s")), .assign (cell "upper" (v "x")) (upper (v "s")),
      when (land (v "changed") (call "itv_is_bot" [v "s"])) [setState sBot (n 1)],
      ret (v "changed")] }

def loadB : SlangFunctionDecl :=
  { retType := itv, name := "load_b", params := [param "b" int, param "x" int],
    body := [ret (mk (cell "lower" (v "x")) (cell "upper" (v "x")))] }

def codeFields : List S :=
  [.declInit (.vec .int 4) "c" (codeAt (v "i")), .declInit int "x" (.member (v "c") "y"), .declInit int "y" (.member (v "c") "z"),
   .declInit int "z" (.member (v "c") "w"),
   .declInit itv "r1" (call "load_b" [v "b", v "x"]), .declInit itv "r2" (call "load_b" [v "b", v "y"]),
   .declInit itv "r3" (call "load_b" [v "b", v "z"])]

/-- `PIR::deduce(bytecode)` on the store of block `b`. -/
def deduceBytecodeB : SlangFunctionDecl :=
  { retType := bool, name := "deduce_bytecode_b", params := [param "b" int, param "i" (.scalar .uint)],
    body := codeFields ++ [
      .expr (call "deduce" [.member (v "c") "x", v "r1", v "r2", v "r3"]),
      .declInit bool "changed" (call "embed_b" [v "b", v "x", v "r1"]),
      .assign (v "changed") (lor (call "embed_b" [v "b", v "y", v "r2"]) (v "changed")),
      .assign (v "changed") (lor (call "embed_b" [v "b", v "z", v "r3"]) (v "changed")),
      ret (v "changed")] }

def askBytecodeB : SlangFunctionDecl :=
  { retType := bool, name := "ask_bytecode_b", params := [param "b" int, param "i" (.scalar .uint)],
    body := codeFields ++ [ret (call "ask" [.member (v "c") "x", v "r1", v "r2", v "r3"])] }

def copyStore (fromLower fromUpper toLower toUpper : String) (fromBase toBase : E) : S :=
  loopOver "k" vars
    [.assign (.index (v toLower) (add toBase (v "k"))) (.index (v fromLower) (add fromBase (v "k"))),
     .assign (.index (v toUpper) (add toBase (v "k"))) (.index (v fromUpper) (add fromBase (v "k")))]

def blockBase : E := mul (v "b") vars
def zeroBase : E := n 0

/-- The propagation step of `propagate` in the source: fixpoint, then solution test. -/
-- With `atomic`, the shared bound is lowered with `InterlockedMin`, for blocks that run at the same time on a GPU; the cpp target has no buffer atomics.
def propagateFn (atomic : Bool) : SlangFunctionDecl :=
  { name := "propagate", params := [param "b" int],
    body := [
      setState sLeaf (n 0),
      .declInit bool "changed" (.litBool true),
      .whileLoop (land (v "changed") (eq (stateAt sBot) (n 0)))
        [.assign (v "changed") (.litBool false),
         loopOver "i" (ctl cBytecodes) [when (call "deduce_bytecode_b" [v "b", v "i"]) [.assign (v "changed") (.litBool true)]]],
      .ifThen (eq (stateAt sBot) (n 0))
        [.declInit int "scan" (n 0),
         .whileLoop (land (lt (v "scan") (ctl cBytecodes)) (call "ask_bytecode_b" [v "b", uintOf (v "scan")]))
           [.assign (v "scan") (add (v "scan") (n 1))],
         when (ge (v "scan") (ctl cBytecodes))
           [setState sLeaf (n 1),
            .ifThen (ge (ctl cObjective) (n 0))
              [.declInit int "bound" (cell "lower" (ctl cObjective)),
               when (gt (stateAt sBestBound) (v "bound"))
                 [setState sBestBound (v "bound"),
                  (if atomic then .expr (call "InterlockedMin" [ctl cApproxBest, v "bound"]) else .assign (ctl cApproxBest) (mn (ctl cApproxBest) (v "bound"))),
                  copyStore "lower" "upper" "best_lower" "best_upper" blockBase blockBase,
                  bump sSolutions]]
              [copyStore "lower" "upper" "best_lower" "best_upper" blockBase blockBase, bump sSolutions, .assign (ctl cStop) (n 1)]]]
        [setState sLeaf (n 1)],
      bump sNodes,
      setState sFails (add (stateAt sFails) (pick (eq (stateAt sBot) (n 1)) (n 1) (n 0))),
      setState sDepthMax (mx (stateAt sDepthMax) decDepth),
      when (lor (ge (stateAt sNodes) (ctl cStopNodes)) (ne (ctl cStop) (n 0)))
        [setState sExhaustive (n 0), setState sStop (n 1)]] }

def strategyField (s : E) (k : Nat) : E := .member (.index (v "strategies") s) (match k with | 0 => "x" | 1 => "y" | 2 => "z" | _ => "w")

/-- `push_decision`. -/
def pushDecision : SlangFunctionDecl :=
  let d := decDepth
  let lowerOf := cell "lower" (v "var")
  let upperOf := cell "upper" (v "var")
  { name := "push_decision", params := [param "b" int, param "val_order" int, param "var" int],
    body := [
      when (ge decDepth (sub (ctl cMaxDepth) (n 1))) [.assign (ctl cError) (n 1), .assign (ctl cStop) (n 1), .retVoid],
      setDec d fVar (v "var"), setDec d fCurrent (neg (n 1)),
      .declInit int "lb" lowerOf, .declInit int "ub" upperOf,
      .declInit int "mid" (add (v "lb") (bin "/" (sub (v "ub") (v "lb")) (n 2))),
      .ifThen (eq (v "val_order") (n 0))
        [setDec d fChild0Lower (v "lb"), setDec d fChild0Upper (v "lb"), setDec d fChild1Lower (add (v "lb") (n 1)), setDec d fChild1Upper (v "ub")]
        [.ifThen (eq (v "val_order") (n 1))
          [setDec d fChild0Lower (v "ub"), setDec d fChild0Upper (v "ub"), setDec d fChild1Lower (v "lb"), setDec d fChild1Upper (sub (v "ub") (n 1))]
          [.ifThen (eq (v "val_order") (n 3))
            [setDec d fChild0Lower (v "lb"), setDec d fChild0Upper (v "mid"), setDec d fChild1Lower (add (v "mid") (n 1)), setDec d fChild1Upper (v "ub")]
            [setDec d fChild0Lower (add (v "mid") (n 1)), setDec d fChild0Upper (v "ub"), setDec d fChild1Lower (v "lb"), setDec d fChild1Upper (v "mid")]]],
      setDec d fRope0 (add d (n 1)),
      .ifThen (gt d (n 0))
        [setDec d fRope1 (.index (v "decisions")
          (add (mul (add (mul (v "b") (ctl cMaxDepth)) (sub d (n 1))) (n 8))
               (add (n fRope0) (decAt (sub d (n 1)) fCurrent))))]
        [setDec d fRope1 (neg (n 1))],
      setState sDepth (add d (n 1))] }

/-- A variable is branchable when it is not assigned and has finite bounds. -/
def branchable (lowerE upperE : E) : E := land (ne lowerE upperE) (land (ne lowerE minusInfinity) (ne upperE infinity))

def variableAt : E := pick (eq (strategyField (v "s") 3) (n 0)) (v "i")
  (.index (v "strategy_vars") (add (strategyField (v "s") 2) (v "i")))
def candidateCount : E := pick (eq (strategyField (v "s") 3) (n 0)) vars (strategyField (v "s") 3)

/-- `input_order_split` and `lattice_smallest_split` for strategy `s`; sets `next_unassigned_var` and pushes the decision when a variable is found. -/
def splitStrategy : SlangFunctionDecl :=
  let order := strategyField (v "s") 0
  let lowerAt := cell "lower" (v "var")
  let upperAt := cell "upper" (v "var")
  let scanVar : List S := [.declInit int "var" variableAt]
  { name := "split_strategy", params := [param "b" int, param "s" int],
    body := [
      .declInit int "count" candidateCount, .declInit int "idx" (v "count"),
      .declInit int "order" order,
      .ifThen (lor (eq (v "order") (n 0)) (eq (v "order") (n 5)))
        [.declInit int "i" (stateAt sNextVar),
         .whileLoop (land (lt (v "i") (v "count")) (eq (v "idx") (v "count")))
           (scanVar ++ [when (branchable lowerAt upperAt) [.assign (v "idx") (v "i")], .assign (v "i") (add (v "i") (n 1))]),
         setState sNextVar (v "idx"),
         when (ne (v "idx") (v "count"))
           [.declInit int "i2" (v "idx"), .declInit int "var" (v "i2"),
            .assign (v "var") (pick (eq (strategyField (v "s") 3) (n 0)) (v "i2") (.index (v "strategy_vars") (add (strategyField (v "s") 2) (v "i2")))),
            .expr (call "push_decision" [v "b", strategyField (v "s") 1, v "var"])]]
        [.declInit int "best" (infinity), .declInit bool "found" (.litBool false), .declInit int "first" (v "count"),
         .declInit int "i" (stateAt sNextVar),
         .whileLoop (lt (v "i") (v "count"))
           (scanVar ++ [
             when (branchable lowerAt upperAt)
               [.declInit int "key" (pick (eq (v "order") (n 1)) (sub upperAt lowerAt)
                  (pick (eq (v "order") (n 2)) (neg (sub upperAt lowerAt)) (pick (eq (v "order") (n 4)) (neg upperAt) lowerAt))),
                when (lor (.un "!" (v "found")) (lt (v "key") (v "best"))) [.assign (v "best") (v "key"), .assign (v "found") (.litBool true)],
                when (eq (v "first") (v "count")) [.assign (v "first") (v "i")]],
             .assign (v "i") (add (v "i") (n 1))]),
         when (v "found")
           [setState sNextVar (v "first"),
            .declInit int "pick" (v "count"),
            .assign (v "i") (v "first"),
            .whileLoop (land (lt (v "i") (v "count")) (eq (v "pick") (v "count")))
              (scanVar ++ [
                when (land (branchable lowerAt upperAt)
                  (eq (pick (eq (v "order") (n 1)) (sub upperAt lowerAt)
                    (pick (eq (v "order") (n 2)) (neg (sub upperAt lowerAt)) (pick (eq (v "order") (n 4)) (neg upperAt) lowerAt))) (v "best")))
                  [.assign (v "pick") (v "i")],
                .assign (v "i") (add (v "i") (n 1))]),
            .declInit int "chosen" (pick (eq (strategyField (v "s") 3) (n 0)) (v "pick")
              (.index (v "strategy_vars") (add (strategyField (v "s") 2) (v "pick")))),
            .expr (call "push_decision" [v "b", strategyField (v "s") 1, v "chosen"])]]] }

/-- `BlockData::split`. -/
def splitFn : SlangFunctionDecl :=
  { retType := bool, name := "split", params := [param "b" int],
    body := [
      .declInit int "current_depth" decDepth,
      setDec decDepth fVar (neg (n 1)),
      .declInit bool "found" (.litBool false),
      .whileLoop (land (.un "!" (v "found")) (lt (stateAt sStrategy) (ctl cStrategies)))
        [.expr (call "split_strategy" [v "b", stateAt sStrategy]),
         .ifThen (ge (decAt (v "current_depth") fVar) (n 0))
           [.assign (v "found") (.litBool true)]
           [bump sStrategy, setState sNextVar (n 0)]],
      ret (v "found")] }

def childFn : SlangFunctionDecl :=
  { retType := itv, name := "child", params := [param "b" int, param "d" int, param "k" int],
    body := [ret (pick (eq (v "k") (n 0))
      (mk (decAt (v "d") fChild0Lower) (decAt (v "d") fChild0Upper))
      (mk (decAt (v "d") fChild1Lower) (decAt (v "d") fChild1Upper)))] }

def currentChildFn : SlangFunctionDecl :=
  { retType := itv, name := "current_child", params := [param "b" int, param "d" int],
    body := [ret (call "child" [v "b", v "d", decAt (v "d") fCurrent])] }

def nextChildFn : SlangFunctionDecl :=
  { retType := itv, name := "next_child", params := [param "b" int, param "d" int],
    body := [setDec (v "d") fCurrent (add (decAt (v "d") fCurrent) (n 1)), ret (call "current_child" [v "b", v "d"])] }

def decVar (d : E) : E := decAt d fVar

def globalBuffers : List SlangBinding :=
  [global "lower" (.rwBuf int) 0, global "upper" (.rwBuf int) 1, global "root_lower" (.roBuf int) 2, global "root_upper" (.roBuf int) 3,
   global "snap_lower" (.rwBuf int) 4, global "snap_upper" (.rwBuf int) 5, global "best_lower" (.rwBuf int) 6, global "best_upper" (.rwBuf int) 7,
   global "code" (.roBuf (.vec .int 4)) 8, global "strategies" (.roBuf (.vec .int 4)) 9, global "strategy_vars" (.roBuf int) 10,
   global "decisions" (.rwBuf int) 11, global "state" (.rwBuf int) 12, global "control" (.rwBuf int) 13]

def objectiveStep : List S :=
  [when (ge (ctl cObjective) (n 0))
    [when (ne (ctl cApproxBest) infinity)
      [.expr (call "embed_b" [v "b", ctl cObjective, mk minusInfinity (sub (ctl cApproxBest) (n 1))]),
       .expr (call "embed_b" [v "b", ctl cObjective, mk minusInfinity (sub (stateAt sBestBound) (n 1))])],
     when (eq (ctl cApproxBest) minusInfinity) [setState sStop (n 1), .assign (ctl cStop) (n 1)]]]

/-- Restore the store from the snapshot of the subproblem root and re-apply the decisions on the path (section IV of the source). -/
def backtrack : List S :=
  [setState sDepth (.index (v "decisions")
     (add (mul (add (mul (v "b") (ctl cMaxDepth)) (sub decDepth (n 1))) (n 8))
          (add (n fRope0) (decAt (sub decDepth (n 1)) fCurrent)))),
   .ifThen (eq decDepth (neg (n 1))) [setState sInner (n 0)]
     [copyStore "snap_lower" "snap_upper" "lower" "upper" blockBase blockBase,
      setState sBot (n 0),
      .declInit bool "again" (.litBool true),
      .whileLoop (v "again")
        [.assign (v "again") (.litBool false),
         .forCount "i" (.litUint 0) (uintOf (sub decDepth (n 1)))
           [when (call "embed_b" [v "b", decVar (call "int" [v "i"]), call "current_child" [v "b", call "int" [v "i"]]]) [.assign (v "again") (.litBool true)]]],
      .expr (call "embed_b" [v "b", decVar (sub decDepth (n 1)), call "next_child" [v "b", sub decDepth (n 1)]]),
      setState sStrategy (stateAt sSnapStrategy), setState sNextVar (stateAt sSnapNextVar)]]

def solveStep : List S :=
  objectiveStep ++
  [when (eq (stateAt sStop) (n 0))
    [.expr (call "propagate" [v "b"]),
     when (eq (stateAt sLeaf) (n 0))
       [when (eq decDepth (n 0))
          [copyStore "lower" "upper" "snap_lower" "snap_upper" blockBase blockBase,
           setState sSnapStrategy (stateAt sStrategy), setState sSnapNextVar (stateAt sNextVar)],
        .ifThen (call "split" [v "b"])
          [.expr (call "embed_b" [v "b", decVar (sub decDepth (n 1)), call "next_child" [v "b", sub decDepth (n 1)]])]
          [setState sLeaf (n 1), setState sExhaustive (n 0)]],
     when (eq (stateAt sLeaf) (n 1))
       [.ifThen (eq decDepth (n 0)) [setState sInner (n 0)] backtrack]]]

def diveStep : List S :=
  [.expr (call "propagate" [v "b"]),
   when (eq (stateAt sLeaf) (n 0))
     [.ifThen (call "split" [v "b"])
        [setState sRemaining (sub (stateAt sRemaining) (n 1)), setState sDepth (sub decDepth (n 1)),
         .declInit int "branch" (bin "&" (bin ">>" (stateAt sSubproblem) (stateAt sRemaining)) (n 1)),
         .expr (call "embed_b" [v "b", decVar (n 0), call "child" [v "b", n 0, v "branch"]])]
        [setState sLeaf (n 1), setState sExhaustive (n 0)]]]

/-- Stop this slice after the node budget (`control[13]`, 0 for none) is used. -/
def sliceCheck : S :=
  when (land (gt (ctl cSliceNodes) (n 0)) (ge (sub (stateAt sNodes) (stateAt sSliceStart)) (ctl cSliceNodes)))
    [setState sYield (n 1)]

/-- With `control[14]` set, the block waits in `phaseAwait` for a coordinator to assign its next subproblem, so blocks can run in separate guests on separate machines. -/
def initBlock : List S :=
  [setState sBestBound infinity, setState sExhaustive (n 1), setState sSubproblem (v "b"), setState sStop (n 0),
   .ifThen (ne (ctl cExternal) (n 0)) [setState sPhase (n phaseAwait)] [setState sPhase (n phaseStart)]]

def startSubproblem : List S :=
  [.ifThen (ge (stateAt sSubproblem) (v "num_subproblems"))
     [setState sPhase (n phaseDone)]
     [setState sStrategy (n 0), setState sNextVar (n 0), setState sDepth (n 0), setState sBot (n 0),
      copyStore "root_lower" "root_upper" "lower" "upper" zeroBase blockBase,
      setState sRemaining (ctl cPower), setState sLeaf (n 0), setState sPhase (n phaseDive)]]

/-- The coordinator cancels the subproblem in hand (another node finished it first): drop it and wait for the next one. -/
def cancelCheck : S :=
  when (ne (ctl cCancel) (n 0)) [.assign (ctl cCancel) (n 0), setState sInner (n 0), setState sLeaf (n 1), setState sRemaining (n 0), setState sPhase (n phaseNext)]

/-- One iteration of the dive, or the end of it: sections D and E of the source. -/
def diveIteration (atomic : Bool) : List S :=
  [cancelCheck, .ifThen (land (land (gt (stateAt sRemaining) (n 0)) (eq (stateAt sLeaf) (n 0))) (eq (stateAt sStop) (n 0)))
     (diveStep ++ [sliceCheck])
     [.ifThen (land (eq (stateAt sLeaf) (n 1)) (eq (stateAt sStop) (n 0)))
        [.declInit int "skip_to" (bin "<<" (add (bin ">>" (stateAt sSubproblem) (stateAt sRemaining)) (n 1)) (stateAt sRemaining)),
         (if atomic then .expr (call "InterlockedMax" [ctl cNextSubproblem, v "skip_to"]) else .assign (ctl cNextSubproblem) (mx (ctl cNextSubproblem) (v "skip_to"))), setState sPhase (n phaseNext)]
        [.ifThen (eq (stateAt sStop) (n 0))
           [when (ne (ctl cEps) (n 0)) [setState sStrategy (mx (n 1) (stateAt sStrategy)), setState sNextVar (n 0)],
            setState sInner (n 1), setState sPhase (n phaseSearch)]
           [setState sPhase (n phaseDone)]]]]

/-- One iteration of the search loop of section F. -/
def searchIteration : List S :=
  [cancelCheck, .ifThen (land (ne (stateAt sInner) (n 0)) (eq (stateAt sStop) (n 0)))
     (solveStep ++ [sliceCheck])
     [setState sPhase (n phaseNext)]]

def nextSubproblem (atomic : Bool) : List S :=
  [.ifThen (eq (stateAt sStop) (n 0))
     [.ifThen (ne (ctl cExternal) (n 0))
        [setState sPhase (n phaseAwait)]
        (if atomic
          then [.decl int "claimed", .expr (call "InterlockedAdd" [ctl cNextSubproblem, n 1, v "claimed"]), setState sSubproblem (v "claimed"), setState sPhase (n phaseStart)]
          else [setState sSubproblem (ctl cNextSubproblem), .assign (ctl cNextSubproblem) (add (ctl cNextSubproblem) (n 1)), setState sPhase (n phaseStart)])]
     [setState sPhase (n phaseDone)]]

/-- The block loop of the source as a state machine over `state[b][phase]`, so a slice can stop after any iteration and the next call resumes. -/
def solveFn (atomic : Bool) : SlangFunctionDecl :=
  { attrs := [.shaderCompute, .numthreads 1 1 1], name := "solve", params := [⟨"tid", .vec .uint 3, .svDispatchThreadId, none, none, .qIn⟩],
    body := [
      .declInit int "b" (call "int" [.member (v "tid") "x"]),
      when (ge (v "b") (ctl cBlocks)) [.retVoid],
      when (eq (stateAt sPhase) (n 0)) initBlock,
      .declInit int "num_subproblems" (bin "<<" (n 1) (ctl cPower)),
      setState sYield (n 0), setState sSliceStart (stateAt sNodes),
      .whileLoop (land (land (ne (stateAt sPhase) (n phaseDone)) (ne (stateAt sPhase) (n phaseAwait))) (eq (stateAt sYield) (n 0)))
        [when (eq (stateAt sPhase) (n phaseStart)) startSubproblem,
         when (eq (stateAt sPhase) (n phaseDive)) (diveIteration atomic),
         when (eq (stateAt sPhase) (n phaseSearch)) searchIteration,
         when (eq (stateAt sPhase) (n phaseNext)) (nextSubproblem atomic)]] }

def solveModule (atomic : Bool := false) : SlangShaderModule :=
  { shaderModule with
    globals := globalBuffers,
    functions := shaderModule.functions ++
      [embedB, loadB, deduceBytecodeB, askBytecodeB, propagateFn atomic, pushDecision, splitStrategy, splitFn, childFn, currentChildFn, nextChildFn, solveFn atomic] }

end Turbo

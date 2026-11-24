#!/bin/bash
# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Judge the log of a coordinator run of the cluster test (scout, power 5, one fast worker, one worker that holds its first job, one that dies on its first assignment):
# the objective is 511, a node was lost and its subproblem redone, a slow node's subproblem was stolen, and the run summary is there. Usage: tools/cluster_check.sh COORDINATOR.log
log=$1
ok=1
grep -q "objective \[511, 511\]" "$log" || { echo "FAIL: objective is not 511"; ok=0; }
grep -qE "[0-9]+ of 32 subproblems done" "$log" || { echo "FAIL: no summary"; ok=0; }
grep -q "lost; subproblem" "$log" || { echo "FAIL: no lost node"; ok=0; }
grep -qE "[1-9][0-9]* steal" "$log" || { echo "FAIL: no steal"; ok=0; }
[ $ok = 1 ] && echo "cluster test: ok"
exit $((1 - ok))

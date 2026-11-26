# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
{ pkgs, system-manager, toplevel, foundationdb }:

# The service on an Ubuntu 24.04 root file system in systemd-nspawn, activated by system-manager: the same goals as the NixOS
# test, with the pages in FoundationDB or in a SQLite file
let
  store = if foundationdb then "foundationdb" else "sqlite";
  fdbcli = "${toplevel.config.services.foundationdb.package}/bin/fdbcli";
in
system-manager.lib.containerTest.makeContainerTest {
  hostPkgs = pkgs;
  name = "frontier-ubuntu-${store}";
  inherit toplevel;
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.activate()
    machine.wait_for_unit("system-manager.target")
    ${if foundationdb then ''machine.wait_for_unit("foundationdb.service")'' else ""}
    machine.wait_for_unit("frontier.service")
    machine.wait_for_open_port(9920)

    def ask(goal: str) -> str:
        return machine.succeed(
            "curl -sf -X POST localhost:9920/ -d '"
            + '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"text":"' + goal + '"}]}}}'
            + "'"
        )

    assert 'reached\\":true' in ask("look-dev"), "look-dev was not planned"
    assert "undeclared_goal" in ask("reach-gpu-training-99"), "an undeclared goal was not refused"
  '' + (if foundationdb then ''
    machine.fail("test -e /var/lib/private/frontier/frontier.sqlite")
    keys = machine.succeed("${fdbcli} --exec 'getrange weft/db/frontier/ weft/db/frontier0 5000' --timeout 60")
    assert "weft/db/frontier/HEAD" in keys, keys
  '' else ''
    machine.succeed("test -s /var/lib/private/frontier/frontier.sqlite")
  '');
}

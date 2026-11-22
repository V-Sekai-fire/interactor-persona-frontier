{ pkgs, self }:

pkgs.testers.runNixOSTest {
  name = "frontier-service";

  nodes.machine = { ... }: {
    imports = [ self.nixosModules.default ];
    virtualisation.memorySize = 2048;
    services.frontier = {
      enable = true;
      foundationdb = true;
      # the test's own package set is read-only, so the packages are passed in, not added by the overlay
      package = pkgs.frontier;
      weftfdb = pkgs.frontier-weftfdb;
    };
  };

  testScript = ''
    machine.wait_for_unit("foundationdb.service")
    machine.wait_for_unit("frontier.service")
    machine.wait_for_open_port(9920)

    ask = lambda goal: machine.succeed(
        "curl -sf -X POST localhost:9920/ -d '"
        + '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","parts":[{"text":"' + goal + '"}]}}}'
        + "'"
    )

    # positive: a goal the pipeline has is planned; negative: one it has not is refused by name
    assert 'reached\\":true' in ask("look-dev"), "look-dev was not planned"
    assert "undeclared_goal" in ask("reach-gpu-training-99"), "an undeclared goal was not refused"

    # the pages are in FoundationDB, not a local file
    machine.fail("test -e /var/lib/frontier/frontier.sqlite")
    keys = machine.succeed("fdbcli --exec 'getrange weft/db/frontier/ weft/db/frontier0 20' --timeout 10")
    assert "weft/db/frontier/HEAD" in keys, keys
    assert '"kind":"request"' in keys, keys
  '';
}

{ pkgs, self }:

pkgs.testers.runNixOSTest {
  name = "frontier-service";

  nodes.machine = { ... }: {
    imports = [ self.nixosModules.default ];
    virtualisation.memorySize = 2048;
    services.frontier.enable = true;
    # the test's own package set is read-only, so the package is passed in, not added by the overlay
    services.frontier.package = pkgs.frontier;
  };

  testScript = ''
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

    # the state lives under /var/lib/frontier, not in the read-only package
    machine.succeed("test -s /var/lib/private/frontier/frontier.sqlite")
  '';
}

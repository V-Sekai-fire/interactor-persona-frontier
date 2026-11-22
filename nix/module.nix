{ config, lib, pkgs, ... }:

let
  cfg = config.services.frontier;
in
{
  options.services.frontier = {
    enable = lib.mkEnableOption "the frontier planner";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.frontier;
      defaultText = lib.literalExpression "pkgs.frontier";
      description = "The planner package; add this flake's overlay to get pkgs.frontier.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "IPv4 address to bind. The write routes (practice, experience, learn) have no credential of their own, so keep this on loopback unless something in front of it checks callers.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9920;
      description = "HTTP port.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.frontier = {
      description = "frontier planner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment.FRONTIER_DB = "/var/lib/frontier/frontier.sqlite";
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --host ${cfg.host} --port ${toString cfg.port}";
        # the planner reads its seed files from ./seeds
        WorkingDirectory = "${cfg.package}/share/frontier";
        StateDirectory = "frontier";
        DynamicUser = true;
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}

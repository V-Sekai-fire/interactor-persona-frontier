# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
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

    weftfdb = lib.mkOption {
      type = lib.types.package;
      default = pkgs.frontier-weftfdb;
      defaultText = lib.literalExpression "pkgs.frontier-weftfdb";
      description = "The FoundationDB VFS module, used when foundationdb is on.";
    };

    foundationdb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Keep the pages in FoundationDB, through the weftfdb VFS, on a FoundationDB service this module starts on the same host. Off keeps them in a SQLite file.";
    };

    osquery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run osqueryd beside the planner and log the load average every 60 seconds, so the box reports how busy it is.";
    };

    osqueryInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Seconds between the load samples osqueryd logs, when osquery is on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.foundationdb = lib.mkIf cfg.foundationdb {
      enable = true;
      package = lib.mkDefault pkgs.foundationdb;
    };

    services.osquery = lib.mkIf cfg.osquery {
      enable = true;
      settings.schedule.load_average = {
        query = "SELECT period, average FROM load_average;";
        interval = cfg.osqueryInterval;
        # a snapshot logs every run, where a differential query logs nothing on its first
        snapshot = true;
      };
    };

    # osqueryd keeps its database and extension socket here and does not create the directory itself
    systemd.tmpfiles.rules = lib.optional cfg.osquery "d /var/osquery 0755 root root -";

    systemd.services.frontier = {
      description = "frontier planner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ lib.optional cfg.foundationdb "foundationdb.service";
      environment =
        if cfg.foundationdb then {
          FRONTIER_DB = "file:frontier?vfs=weft_fdb";
          FRONTIER_VFS_EXT = "${cfg.weftfdb}/lib/weftfdb";
          WEFT_FDB_CLUSTER_FILE = "/etc/foundationdb/fdb.cluster";
        } else {
          FRONTIER_DB = "/var/lib/frontier/frontier.sqlite";
        };
      requires = lib.optional cfg.foundationdb "foundationdb.service";
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

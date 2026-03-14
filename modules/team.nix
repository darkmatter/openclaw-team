# Dark Matter OpenClaw team module
#
# This module provides:
#   1. Team infrastructure: sops secrets, SSH→age key, shared workspace (GDrive)
#   2. Sensible defaults for programs.openclaw config (all lib.mkDefault, easily overridden)
#   3. acpx agent config for Volt VMs
#
# Usage:
#   openclaw-dm = {
#     enable = true;
#     tailscaleMachineName = "my-macbook";
#   };
#
#   # Override any openclaw config normally:
#   programs.openclaw.instances.default.config.agents.list = [ ... ];
#
{ config, lib, pkgs, inputs ? {}, ... }:

let
  cfg = config.openclaw-dm;

  tailnet = "tail6277a6.ts.net";

  gatewayUrl = "wss://${cfg.tailscaleMachineName}.${tailnet}";

  primaryGatewayUrl =
    if cfg.role == "primary" then gatewayUrl
    else "wss://${cfg.primaryHost}.${tailnet}";

  models = {
    SONNET = "anthropic/claude-sonnet-4-6";
    OPUS = "anthropic/claude-opus-4-6";
    GPT = "openai/gpt-5.4";
    AUTO = "openrouter/auto";
  };

  voltVMs = [ 1 2 3 4 ];

  isPrimary = cfg.role == "primary";
  isRemote = cfg.role == "remote-personal" || cfg.role == "remote-server";

  # Shared workspace sync
  syncScript = pkgs.writeShellScript "openclaw-shared-sync" ''
    set -euo pipefail
    SHARED="$HOME/.openclaw/workspace/shared"
    REMOTE="openclaw-team:"
    mkdir -p "$SHARED"

    ${if cfg.sharedWorkspace.direction == "bisync" then ''
      ${pkgs.rclone}/bin/rclone bisync "$SHARED" "$REMOTE" \
        --create-empty-src-dirs --resilient --recover \
        --conflict-resolve newer --fix-case \
        2>&1 || {
          ${pkgs.rclone}/bin/rclone bisync "$SHARED" "$REMOTE" \
            --create-empty-src-dirs --resync \
            --conflict-resolve newer --fix-case 2>&1
        }
    '' else if cfg.sharedWorkspace.direction == "pull" then ''
      ${pkgs.rclone}/bin/rclone sync "$REMOTE" "$SHARED" 2>&1
    '' else ''
      ${pkgs.rclone}/bin/rclone sync "$SHARED" "$REMOTE" 2>&1
    ''}
  '';

  syncIntervalSeconds = let
    m = builtins.match "([0-9]+)m" cfg.sharedWorkspace.interval;
    s = builtins.match "([0-9]+)s" cfg.sharedWorkspace.interval;
    h = builtins.match "([0-9]+)h" cfg.sharedWorkspace.interval;
  in
    if m != null then (lib.toInt (builtins.head m)) * 60
    else if s != null then lib.toInt (builtins.head s)
    else if h != null then (lib.toInt (builtins.head h)) * 3600
    else 300;

in {

  # ── Options ──────────────────────────────────────────────────────────
  # These control team infrastructure only. OpenClaw config is set via
  # programs.openclaw directly (with lib.mkDefault so you can override).

  options.openclaw-dm = {
    enable = lib.mkEnableOption "Dark Matter OpenClaw team infrastructure";

    tailscaleMachineName = lib.mkOption {
      type = lib.types.str;
      description = "Your Tailscale machine hostname (from `tailscale status`).";
      example = "coopers-mac-studio";
    };

    role = lib.mkOption {
      type = lib.types.enum [ "primary" "remote-personal" "remote-server" ];
      default = "primary";
      description = ''
        primary         = runs gateway locally with Tailscale Funnel
        remote-personal = personal device connecting to your primary
        remote-server   = headless server connecting to a primary
      '';
    };

    primaryHost = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Tailscale name of your primary gateway (required for remote roles).";
    };

    manageSopsSecrets = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-configure sops-nix to decrypt team secrets.";
    };

    sopsIdentityPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra identity paths for sops-nix decryption.";
    };

    sharedWorkspace = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Sync shared/ subdirectory via Google Drive.";
      };

      teamDriveId = lib.mkOption {
        type = lib.types.str;
        default = "0AMjJCQnNMu-AUk9PVA";
        description = "Google Shared Drive ID.";
      };

      folderId = lib.mkOption {
        type = lib.types.str;
        default = "1G8fUAxyuK4Nnslauy-QWkfP4FKATVoGy";
        description = "Folder ID within the Shared Drive.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5m";
        description = "Sync interval.";
      };

      direction = lib.mkOption {
        type = lib.types.enum [ "bisync" "pull" "push" ];
        default = "bisync";
      };
    };
  };

  # ── Config ───────────────────────────────────────────────────────────

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isRemote -> cfg.primaryHost != "";
        message = "openclaw-dm.primaryHost is required when role is ${cfg.role}";
      }
    ];

    home.packages = [ pkgs.ssh-to-age ];

    # ── OpenClaw config defaults ─────────────────────────────────────
    # All lib.mkDefault — override anything by setting it directly in
    # your own programs.openclaw.instances.default.config.

    programs.openclaw.instances.default = {
      enable = lib.mkDefault true;

      config = {
        agents.defaults = {
          compaction.mode = lib.mkDefault "safeguard";
          contextPruning = {
            mode = lib.mkDefault "cache-ttl";
            ttl = lib.mkDefault "1h";
          };
          heartbeat.every = lib.mkDefault "1h";
          maxConcurrent = lib.mkDefault 4;
          model = {
            fallbacks = lib.mkDefault [ models.SONNET models.GPT ];
            primary = lib.mkDefault models.SONNET;
          };
          models = {
            ${models.SONNET} = {};
            ${models.GPT} = { alias = lib.mkDefault "GPT"; };
            ${models.AUTO} = { alias = lib.mkDefault "Auto"; };
          };
        };

        auth.profiles = {
          "anthropic:default" = {
            mode = lib.mkDefault "token";
            provider = lib.mkDefault "anthropic";
          };
          "openai:default" = {
            mode = lib.mkDefault "api_key";
            provider = lib.mkDefault "openai";
          };
          "openrouter:default" = {
            mode = lib.mkDefault "api_key";
            provider = lib.mkDefault "openrouter";
          };
        };

        gateway = {
          auth = {
            mode = lib.mkDefault "password";
            allowTailscale = lib.mkDefault true;
          };
          port = lib.mkDefault 18789;
        } // (
          if isPrimary then {
            mode = lib.mkDefault "local";
            bind = lib.mkDefault "loopback";
            tailscale = {
              mode = lib.mkDefault "funnel";
              resetOnExit = lib.mkDefault true;
            };
            remote = {
              transport = lib.mkDefault "direct";
              url = lib.mkDefault gatewayUrl;
            };
            controlUi.allowedOrigins = lib.mkDefault [ gatewayUrl ];
          } else {
            mode = lib.mkDefault "remote";
            bind = lib.mkDefault "loopback";
            tailscale.mode = lib.mkDefault "off";
            remote = {
              transport = lib.mkDefault "direct";
              url = lib.mkDefault primaryGatewayUrl;
            };
          }
        );

        acp = {
          enabled = lib.mkDefault true;
          backend = lib.mkDefault "acpx";
          defaultAgent = lib.mkDefault "volt-1";
          allowedAgents = lib.mkDefault (
            (map (id: "volt-${toString id}") voltVMs)
            ++ [ "codex" "claude" "pi" ]
          );
          maxConcurrentSessions = lib.mkDefault 8;
          stream = {
            coalesceIdleMs = lib.mkDefault 300;
            maxChunkChars = lib.mkDefault 1200;
          };
          runtime.ttlMinutes = lib.mkDefault 120;
        };

        plugins = {
          allow = lib.mkDefault [ "acpx" ];
          entries.acpx = {
            enabled = lib.mkDefault true;
            config = {
              permissionMode = lib.mkDefault "approve-all";
              nonInteractivePermissions = lib.mkDefault "deny";
            };
          };
        };

        tools = {
          agentToAgent = {
            allow = lib.mkDefault [ "*" ];
            enabled = lib.mkDefault true;
          };
          elevated.enabled = lib.mkDefault true;
          exec = {
            ask = lib.mkDefault "off";
            host = lib.mkDefault "gateway";
            security = lib.mkDefault "full";
          };
          links.enabled = lib.mkDefault true;
          sessions.visibility = lib.mkDefault "all";
          profile = lib.mkDefault "full";
        };

        cron.enabled = lib.mkDefault true;
        env.shellEnv.enabled = lib.mkDefault true;
        session.dmScope = lib.mkDefault "per-channel-peer";
      };
    };

    # ── sops-nix secrets ─────────────────────────────────────────────

    sops = lib.mkIf cfg.manageSopsSecrets {
      age = {
        sshKeyPaths = [
          "/etc/ssh/ssh_host_ed25519_key"
        ] ++ cfg.sopsIdentityPaths;
        keyFile =
          if pkgs.stdenv.isDarwin
          then "${config.home.homeDirectory}/Library/Application Support/sops/age/keys.txt"
          else "${config.home.homeDirectory}/.config/sops/age/keys.txt";
        generateKey = false;
      };

      secrets = {
        openclaw-gateway-password = {
          sopsFile = ../secrets/gateway-password.yaml;
          key = "gateway_password";
        };
        openclaw-volt-password = {
          sopsFile = ../secrets/volt-gateway-password.yaml;
          key = "volt_gateway_password";
          path = "${config.home.homeDirectory}/.config/volt/token";
        };
        openclaw-anthropic-api-key = {
          sopsFile = ../secrets/anthropic-api-key.yaml;
          key = "anthropic_api_key";
        };
        openclaw-openai-api-key = {
          sopsFile = ../secrets/openai-api-key.yaml;
          key = "openai_api_key";
        };
        openclaw-openrouter-api-key = {
          sopsFile = ../secrets/openrouter-api-key.yaml;
          key = "openrouter_api_key";
        };
      } // lib.optionalAttrs cfg.sharedWorkspace.enable {
        openclaw-gdrive-sa-key = {
          sopsFile = ../secrets/gdrive-sa-key.yaml;
          key = "gdrive_sa_key_json";
        };
      };
    };

    # ── Activation scripts ───────────────────────────────────────────

    # Persist SSH host key as age private key for sops CLI
    home.activation.sopsAgeFromHostKey = lib.hm.dag.entryBefore [ "sopsNix" ] ''
      AGE_DIR="${if pkgs.stdenv.isDarwin
        then "${config.home.homeDirectory}/Library/Application Support/sops/age"
        else "${config.home.homeDirectory}/.config/sops/age"}"
      AGE_KEYFILE="$AGE_DIR/keys.txt"
      HOST_KEY="/etc/ssh/ssh_host_ed25519_key"
      MARKER="# auto-converted from ssh host key"

      if [[ -f "$HOST_KEY" ]] && command -v ssh-to-age >/dev/null 2>&1; then
        mkdir -p "$AGE_DIR"
        AGE_PRIVATE="$(ssh-to-age -private-key -i "$HOST_KEY" 2>/dev/null)" || true
        if [[ -n "$AGE_PRIVATE" ]]; then
          if ! grep -qF "$AGE_PRIVATE" "$AGE_KEYFILE" 2>/dev/null; then
            {
              echo ""
              echo "$MARKER"
              echo "$AGE_PRIVATE"
            } >> "$AGE_KEYFILE"
            chmod 600 "$AGE_KEYFILE"
          fi
        fi
      fi
    '';

    # Write API keys env file
    home.activation.openclawTeamEnv = lib.mkIf cfg.manageSopsSecrets (
      lib.hm.dag.entryAfter [ "sopsNix" ] ''
        _envFile="$HOME/.openclaw/env.team"
        mkdir -p "$(dirname "$_envFile")"
        {
          echo "ANTHROPIC_API_KEY=$(cat ${config.sops.secrets.openclaw-anthropic-api-key.path} 2>/dev/null)"
          echo "OPENAI_API_KEY=$(cat ${config.sops.secrets.openclaw-openai-api-key.path} 2>/dev/null)"
          echo "OPENROUTER_API_KEY=$(cat ${config.sops.secrets.openclaw-openrouter-api-key.path} 2>/dev/null)"
        } > "$_envFile"
        chmod 600 "$_envFile"
      ''
    );

    # Wire gateway password from sops into openclaw config
    home.activation.openclawTeamGatewayAuth = lib.mkIf cfg.manageSopsSecrets (
      lib.hm.dag.entryAfter [ "sopsNix" "openclawConfigFiles" ] ''
        OC_JSON="$HOME/.openclaw/openclaw.json"
        if [[ -f "$OC_JSON" ]] && command -v jq >/dev/null 2>&1; then
          _pw="$(cat ${config.sops.secrets.openclaw-gateway-password.path} 2>/dev/null)" || true
          if [[ -n "$_pw" ]]; then
            _tmp="$(mktemp)"
            ${pkgs.jq}/bin/jq --arg pw "$_pw" '.gateway.auth.password = $pw | .gateway.remote.password = $pw' "$OC_JSON" > "$_tmp" && mv "$_tmp" "$OC_JSON"
          fi
        fi
      ''
    );

    # ── Shared workspace (GDrive) ────────────────────────────────────

    home.activation.openclawSharedWorkspace = lib.mkIf cfg.sharedWorkspace.enable (
      lib.hm.dag.entryAfter [ "sopsNix" "linkGeneration" ] ''
        mkdir -p "$HOME/.openclaw/workspace/shared"
        mkdir -p "$HOME/.config/rclone"

        SA_KEY_PATH="$HOME/.config/openclaw-gdrive-sa.json"
        SA_SOPS_PATH="${config.sops.secrets.openclaw-gdrive-sa-key.path}"
        if [[ -f "$SA_SOPS_PATH" ]]; then
          ${pkgs.python3}/bin/python3 ${../scripts/yaml-to-json.py} "$SA_SOPS_PATH" "$SA_KEY_PATH"
          chmod 600 "$SA_KEY_PATH"
        fi

        RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
        if [[ -f "$RCLONE_CONF" ]]; then
          ${pkgs.gnused}/bin/sed -i '/^\[openclaw-team\]/,/^\[/{/^\[openclaw-team\]/d;/^\[/!d;}' "$RCLONE_CONF" 2>/dev/null || true
        fi
        cat >> "$RCLONE_CONF" <<EOF

[openclaw-team]
type = drive
scope = drive
service_account_file = $SA_KEY_PATH
team_drive = ${cfg.sharedWorkspace.teamDriveId}
root_folder_id = ${cfg.sharedWorkspace.folderId}
EOF
      ''
    );

    launchd.agents.openclaw-shared-sync = lib.mkIf (cfg.sharedWorkspace.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [ "${syncScript}" ];
        StartInterval = syncIntervalSeconds;
        StandardOutPath = "/tmp/openclaw-shared-sync.log";
        StandardErrorPath = "/tmp/openclaw-shared-sync.log";
        RunAtLoad = true;
      };
    };

    systemd.user.services.openclaw-shared-sync = lib.mkIf (cfg.sharedWorkspace.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Sync OpenClaw shared workspace via rclone (GDrive)";
      Service = {
        Type = "oneshot";
        ExecStart = "${syncScript}";
      };
    };

    systemd.user.timers.openclaw-shared-sync = lib.mkIf (cfg.sharedWorkspace.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Periodic OpenClaw shared workspace sync";
      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.sharedWorkspace.interval;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # ── acpx agent config ────────────────────────────────────────────

    home.file.".acpx/config.json".text = builtins.toJSON {
      agents = builtins.listToAttrs (map (id: {
        name = "volt-${toString id}";
        value = {
          command = "openclaw acp --url wss://volt-${toString id}.${tailnet} --password-file ~/.config/volt/token";
        };
      }) voltVMs);
    };
  };
}

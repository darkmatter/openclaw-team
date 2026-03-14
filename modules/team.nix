# Dark Matter OpenClaw team module
#
# Usage:
#   openclaw-dm = {
#     enable = true;
#     tailscaleMachineName = "my-macbook";   # your Tailscale hostname
#     role = "primary";                       # runs gateway locally
#   };
#
#   # Multi-machine (desktop + laptop):
#   # Desktop:  role = "primary";   tailscaleMachineName = "my-desktop";
#   # Laptop:   role = "remote-personal"; primaryHost = "my-desktop";
#
{ config, lib, pkgs, inputs ? {}, ... }:

let
  cfg = config.openclaw-dm;

  tailnet = "tail6277a6.ts.net";
  gatewayPort = 18789;

  # Compute gateway URL from tailscale machine name
  gatewayUrl = "wss://${cfg.tailscaleMachineName}.${tailnet}";

  # For remote roles, compute the primary URL
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

  defaultAgentConfig = model: {
    agentDir = "~/.openclaw/agents/main/agent";
    default = true;
    id = "main";
    identity = {
      emoji = "🦞";
      name = "OpenClaw";
      theme = "ayu";
    };
    inherit model;
    name = "Main Agent";
    sandbox.mode = "off";
    subagents.allowAgents = [ "*" ];
    tools = {
      allow = [ "*" ];
      deny = [ "canvas" ];
      elevated.enabled = true;
      profile = "coding";
    };
    workspace = "~/.openclaw/workspace";
  };

  coderAgent = model: {
    agentDir = "~/.openclaw/agents/coder/agent";
    default = false;
    id = "coder";
    identity = {
      emoji = "⚡";
      name = "Volt";
      theme = "ayu";
    };
    inherit model;
    name = "Coding Agent";
    sandbox.mode = "off";
    subagents.allowAgents = [ "main" ];
    tools = {
      allow = [ "*" ];
      deny = [ "canvas" ];
      elevated.enabled = true;
      profile = "coding";
    };
    workspace = "~/.openclaw/workspace";
  };

  isPrimary = cfg.role == "primary";
  isRemote = cfg.role == "remote-personal" || cfg.role == "remote-server";
  isServer = cfg.role == "remote-server";

  # Shared workspace sync helpers
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
  options.openclaw-dm = {
    enable = lib.mkEnableOption "Dark Matter OpenClaw team config";

    tailscaleMachineName = lib.mkOption {
      type = lib.types.str;
      description = ''
        Your Tailscale machine hostname (as shown in `tailscale status`).
        Used to compute the gateway URL: wss://<name>.${tailnet}
      '';
      example = "coopers-mac-studio";
    };

    role = lib.mkOption {
      type = lib.types.enum [ "primary" "remote-personal" "remote-server" ];
      default = "primary";
      description = ''
        primary         = runs the gateway locally with Tailscale Funnel.
                          This is the main machine you work from.
        remote-personal = connects to your primary gateway from another
                          personal device (e.g. laptop → desktop).
        remote-server   = headless server that connects to a primary gateway.
                          No interactive features, optimized for CI/automation.
      '';
    };

    primaryHost = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Tailscale machine name of your primary gateway.
        Only used when role is remote-personal or remote-server.
      '';
      example = "my-mac-studio";
    };

    gateway.port = lib.mkOption {
      type = lib.types.port;
      default = gatewayPort;
      description = "Gateway port";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = models.SONNET;
      description = "Default model for agents";
    };

    enableCoder = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the coder agent alongside main";
    };

    secrets = {
      passwordPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if config.sops.secrets ? "openclaw-gateway-password"
          then config.sops.secrets.openclaw-gateway-password.path
          else null;
        defaultText = lib.literalExpression "sops-decrypted gateway_password";
        description = "Path to decrypted gateway password (auto-set from sops-nix)";
      };
      tokenPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to decrypted gateway token (agenix/sops-nix)";
      };
      voltPasswordPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = if config.sops.secrets ? "openclaw-volt-password"
          then config.sops.secrets.openclaw-volt-password.path
          else null;
        defaultText = lib.literalExpression "sops-decrypted volt_gateway_password";
        description = "Path to decrypted Volt VM password for ACP (auto-set from sops-nix)";
      };
    };

    manageSopsSecrets = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-configure sops-nix to decrypt team secrets";
    };

    sopsIdentityPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra age/ssh identity paths for sops-nix decryption";
    };

    sharedWorkspace = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Sync a shared/ subdirectory in the workspace via rclone (Google Drive)";
      };

      folderId = lib.mkOption {
        type = lib.types.str;
        default = "12VTEdvFB6CyoGvrbWsVhUGqPMy_S2j6X";
        description = ''
          Google Drive folder ID for the shared workspace.
          Default: "OpenClaw Team Workspace" folder in darkmatter.io Drive.
          The folder must be shared with the service account email.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5m";
        description = "Sync interval";
      };

      direction = lib.mkOption {
        type = lib.types.enum [ "bisync" "pull" "push" ];
        default = "bisync";
        description = "bisync = two-way; pull = remote→local; push = local→remote";
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra config merged into openclaw.json";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isRemote -> cfg.primaryHost != "";
        message = "openclaw-dm.primaryHost is required when role is ${cfg.role}";
      }
    ];

    programs.openclaw = {
      instances.default = {
        enable = true;

        config = lib.recursiveUpdate ({
          agents = {
            list = [ (defaultAgentConfig cfg.model) ]
              ++ lib.optional cfg.enableCoder (coderAgent cfg.model);
            defaults = {
              compaction.mode = "safeguard";
              contextPruning = { mode = "cache-ttl"; ttl = "1h"; };
              heartbeat.every = "1h";
              maxConcurrent = 4;
              model = {
                fallbacks = [ models.SONNET models.GPT ];
                primary = cfg.model;
              };
              models = {
                ${models.SONNET} = {};
                ${models.GPT} = { alias = "GPT"; };
                ${models.AUTO} = { alias = "Auto"; };
              };
            };
          };

          auth.profiles = {
            "anthropic:default" = { mode = "token"; provider = "anthropic"; };
            "openai:default" = { mode = "api_key"; provider = "openai"; };
            "openrouter:default" = { mode = "api_key"; provider = "openrouter"; };
          };

          gateway = {
            auth = {
              mode = "password";
              allowTailscale = true;
            } // lib.optionalAttrs (cfg.secrets.tokenPath != null) {
              token = cfg.secrets.tokenPath;
            } // lib.optionalAttrs (cfg.secrets.passwordPath != null) {
              password = cfg.secrets.passwordPath;
            };
            port = cfg.gateway.port;
          } // (
            if isPrimary then {
              mode = "local";
              bind = "loopback";
              tailscale = { mode = "funnel"; resetOnExit = true; };
              remote = {
                transport = "direct";
                url = gatewayUrl;
              } // lib.optionalAttrs (cfg.secrets.passwordPath != null) {
                password = cfg.secrets.passwordPath;
              } // lib.optionalAttrs (cfg.secrets.tokenPath != null) {
                token = cfg.secrets.tokenPath;
              };
              controlUi.allowedOrigins = [ gatewayUrl ];
            } else {
              mode = "remote";
              bind = "loopback";
              tailscale.mode = "off";
              remote = {
                transport = "direct";
                url = primaryGatewayUrl;
              } // lib.optionalAttrs (cfg.secrets.passwordPath != null) {
                password = cfg.secrets.passwordPath;
              } // lib.optionalAttrs (cfg.secrets.tokenPath != null) {
                token = cfg.secrets.tokenPath;
              };
            }
          );

          # ACP config for Volt VMs
          acp = {
            enabled = true;
            backend = "acpx";
            defaultAgent = "volt-1";
            allowedAgents =
              (map (id: "volt-${toString id}") voltVMs)
              ++ [ "codex" "claude" "pi" ];
            maxConcurrentSessions = 8;
            stream = { coalesceIdleMs = 300; maxChunkChars = 1200; };
            runtime.ttlMinutes = 120;
          };

          plugins = {
            allow = [ "acpx" ];
            entries.acpx = {
              enabled = true;
              config = {
                permissionMode = "approve-all";
                nonInteractivePermissions = "deny";
              };
            };
          };

          tools = {
            agentToAgent = { allow = [ "*" ]; enabled = true; };
            elevated.enabled = true;
            exec = { ask = "off"; host = "gateway"; security = "full"; };
            links.enabled = true;
            sessions.visibility = "all";
            profile = "full";
          };

          channels = {};
          bindings = [];
          skills.entries = {};
          messages.tts.auto = "off";
          cron.enabled = true;
          env.shellEnv.enabled = true;
          session.dmScope = "per-channel-peer";
        }) cfg.extraConfig;
      };
    };

    # sops-nix: decrypt team secrets automatically
    sops = lib.mkIf cfg.manageSopsSecrets {
      age = {
        sshKeyPaths = [
          "/etc/ssh/ssh_host_ed25519_key"
          "${config.home.homeDirectory}/.ssh/id_ed25519"
        ] ++ cfg.sopsIdentityPaths;
        keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
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

    # Write API keys env file for the gateway service
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

    # Shared workspace: auto-configure rclone for GDrive using service account
    home.activation.openclawSharedWorkspace = lib.mkIf cfg.sharedWorkspace.enable (
      lib.hm.dag.entryAfter [ "sopsNix" "linkGeneration" ] ''
        mkdir -p "$HOME/.openclaw/workspace/shared"
        mkdir -p "$HOME/.config/rclone"

        # Write SA key JSON from sops secret
        SA_KEY_PATH="$HOME/.config/openclaw-gdrive-sa.json"
        if [[ -f "${config.sops.secrets.openclaw-gdrive-sa-key.path}" ]]; then
          cp "${config.sops.secrets.openclaw-gdrive-sa-key.path}" "$SA_KEY_PATH"
          chmod 600 "$SA_KEY_PATH"
        fi

        # Generate rclone config for the team drive
        RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
        # Remove old team-workspace section if present, then append
        if [[ -f "$RCLONE_CONF" ]]; then
          ${pkgs.gnused}/bin/sed -i '/^\[openclaw-team\]/,/^\[/{ /^\[openclaw-team\]/d; /^\[/!d; }' "$RCLONE_CONF"
        fi
        cat >> "$RCLONE_CONF" <<EOF
        [openclaw-team]
        type = drive
        scope = drive
        service_account_file = $SA_KEY_PATH
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

    # acpx agent config — maps volt-N to openclaw ACP bridges
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

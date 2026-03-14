# Dark Matter OpenClaw team module
#
# Usage in your nix-darwin/home-manager config:
#
#   inputs.openclaw-team.url = "github:darkmatter/openclaw-team";
#
#   imports = [ openclaw-team.homeManagerModules.default ];
#
#   openclaw-dm = {
#     enable = true;
#     hostId = "my-macbook";
#     gateway.url = "wss://my-mac.tail12345.ts.net";
#   };
#
{ config, lib, pkgs, inputs ? {}, ... }:

let
  cfg = config.openclaw-dm;

  tailnet = "tail6277a6.ts.net";
  gatewayPort = 18789;

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

in {
  options.openclaw-dm = {
    enable = lib.mkEnableOption "Dark Matter OpenClaw team config";

    hostId = lib.mkOption {
      type = lib.types.str;
      description = "Unique identifier for this host";
    };

    gateway = {
      url = lib.mkOption {
        type = lib.types.str;
        description = ''
          WebSocket URL of your primary gateway.
          If role=primary, this is YOUR Tailscale Funnel URL (e.g. wss://my-mac.tail12345.ts.net).
          If role=remote, this is the URL you're connecting TO.
        '';
        example = "wss://my-mac-studio.tail6277a6.ts.net";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = gatewayPort;
        description = "Gateway port";
      };
    };

    role = lib.mkOption {
      type = lib.types.enum [ "primary" "remote" ];
      default = "primary";
      description = ''
        primary = runs the gateway locally with Tailscale Funnel.
                  Each team member runs their own primary gateway.
        remote  = connects to another machine's gateway (e.g. laptop → desktop).
      '';
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
        description = "Sync a shared/ subdirectory in the workspace via rclone";
      };

      remote = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "s3:darkmatter-openclaw/shared";
        description = ''
          rclone remote path for the shared workspace.
          Examples:
            s3:my-bucket/openclaw-shared
            dropbox:openclaw/shared
            gdrive:openclaw-shared
          Configure the remote with `rclone config` first.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5m";
        description = "Sync interval (systemd timer format)";
      };

      direction = lib.mkOption {
        type = lib.types.enum [ "bisync" "pull" "push" ];
        default = "bisync";
        description = ''
          bisync = two-way sync (changes propagate both directions)
          pull   = remote → local only
          push   = local → remote only
        '';
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra config merged into openclaw.json";
    };
  };

  config = lib.mkIf cfg.enable {
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
            if cfg.role == "primary" then {
              mode = "local";
              bind = "loopback";
              tailscale = { mode = "funnel"; resetOnExit = true; };
              remote = {
                transport = "direct";
                url = cfg.gateway.url;
              } // lib.optionalAttrs (cfg.secrets.passwordPath != null) {
                password = cfg.secrets.passwordPath;
              } // lib.optionalAttrs (cfg.secrets.tokenPath != null) {
                token = cfg.secrets.tokenPath;
              };
              controlUi.allowedOrigins = [ cfg.gateway.url ];
            } else {
              mode = "remote";
              bind = "loopback";
              tailscale.mode = "off";
              remote = {
                transport = "direct";
                url = cfg.gateway.url;
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

    # Shared workspace sync via rclone
    home.activation.openclawSharedWorkspace = lib.mkIf cfg.sharedWorkspace.enable (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        mkdir -p "$HOME/.openclaw/workspace/shared"
      ''
    );

    launchd.agents.openclaw-shared-sync = lib.mkIf (cfg.sharedWorkspace.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = let
          syncScript = pkgs.writeShellScript "openclaw-shared-sync" ''
            set -euo pipefail
            SHARED="$HOME/.openclaw/workspace/shared"
            REMOTE="${cfg.sharedWorkspace.remote}"
            mkdir -p "$SHARED"

            ${if cfg.sharedWorkspace.direction == "bisync" then ''
              ${pkgs.rclone}/bin/rclone bisync "$SHARED" "$REMOTE" \
                --create-empty-src-dirs \
                --resilient \
                --recover \
                --conflict-resolve newer \
                --fix-case \
                2>&1 || {
                  # First run needs --resync
                  ${pkgs.rclone}/bin/rclone bisync "$SHARED" "$REMOTE" \
                    --create-empty-src-dirs \
                    --resync \
                    --conflict-resolve newer \
                    --fix-case \
                    2>&1
                }
            '' else if cfg.sharedWorkspace.direction == "pull" then ''
              ${pkgs.rclone}/bin/rclone sync "$REMOTE" "$SHARED" 2>&1
            '' else ''
              ${pkgs.rclone}/bin/rclone sync "$SHARED" "$REMOTE" 2>&1
            ''}
          '';
        in [ "${syncScript}" ];
        StartInterval = let
          # Parse interval string to seconds
          m = builtins.match "([0-9]+)m" cfg.sharedWorkspace.interval;
          s = builtins.match "([0-9]+)s" cfg.sharedWorkspace.interval;
          h = builtins.match "([0-9]+)h" cfg.sharedWorkspace.interval;
        in
          if m != null then (lib.toInt (builtins.head m)) * 60
          else if s != null then lib.toInt (builtins.head s)
          else if h != null then (lib.toInt (builtins.head h)) * 3600
          else 300;
        StandardOutPath = "/tmp/openclaw-shared-sync.log";
        StandardErrorPath = "/tmp/openclaw-shared-sync.log";
        RunAtLoad = true;
      };
    };

    # Linux: systemd user service + timer
    systemd.user.services.openclaw-shared-sync = lib.mkIf (cfg.sharedWorkspace.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Sync OpenClaw shared workspace via rclone";
      Service = {
        Type = "oneshot";
        ExecStart = let
          syncScript = pkgs.writeShellScript "openclaw-shared-sync" ''
            set -euo pipefail
            SHARED="$HOME/.openclaw/workspace/shared"
            REMOTE="${cfg.sharedWorkspace.remote}"
            mkdir -p "$SHARED"

            ${if cfg.sharedWorkspace.direction == "bisync" then ''
              ${pkgs.rclone}/bin/rclone bisync "$SHARED" "$REMOTE" \
                --create-empty-src-dirs \
                --resilient \
                --recover \
                --conflict-resolve newer \
                --fix-case \
                2>&1 || {
                  ${pkgs.rclone}/bin/rclone bisync "$SHARED" "$REMOTE" \
                    --create-empty-src-dirs \
                    --resync \
                    --conflict-resolve newer \
                    --fix-case \
                    2>&1
                }
            '' else if cfg.sharedWorkspace.direction == "pull" then ''
              ${pkgs.rclone}/bin/rclone sync "$REMOTE" "$SHARED" 2>&1
            '' else ''
              ${pkgs.rclone}/bin/rclone sync "$SHARED" "$REMOTE" 2>&1
            ''}
          '';
        in "${syncScript}";
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

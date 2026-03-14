# Preset: multi-agent
# Full multi-agent setup with channel routing, TTS, and messaging.
# Based on Cooper's production config. Customize agents/channels to taste.
#
# Requires secrets for channel tokens — set via agenix, sops-nix, or
# override the paths in your own config.
{ lib, ... }:

let
  models = {
    SONNET = "anthropic/claude-sonnet-4-6";
    OPUS = "anthropic/claude-opus-4-6";
  };
in {
  programs.openclaw.instances.default.config = {
    # ── Agents ─────────────────────────────────────────────────────
    agents.list = lib.mkDefault [
      {
        id = "main";
        name = "Main Agent";
        default = true;
        agentDir = "~/.openclaw/agents/main/agent";
        model = models.OPUS;
        identity = { emoji = "🤖"; name = "Assistant"; theme = "ayu"; };
        sandbox.mode = "off";
        subagents.allowAgents = [ "*" ];
        tools = {
          allow = [ "*" ];
          deny = [ "canvas" ];
          elevated.enabled = true;
          profile = "coding";
        };
        workspace = "~/.openclaw/workspace";
      }
      {
        id = "assistant";
        name = "Executive Assistant";
        default = false;
        agentDir = "~/.openclaw/agents/assistant/agent";
        model = models.SONNET;
        identity = { emoji = "👩\u200d💼"; name = "EA"; theme = "ayu"; };
        sandbox.mode = "off";
        subagents.allowAgents = [ "*" ];
        tools = {
          allow = [ "*" ];
          deny = [ "canvas" "sudo" "git" ];
          elevated.enabled = false;
          profile = "messaging";
        };
        workspace = "~/.openclaw/workspace";
      }
      {
        id = "coder";
        name = "Coding Agent";
        default = false;
        agentDir = "~/.openclaw/agents/coder/agent";
        model = models.SONNET;
        identity = { emoji = "⚡"; name = "Volt"; theme = "ayu"; };
        sandbox.mode = "off";
        subagents.allowAgents = [ "main" "assistant" ];
        tools = {
          allow = [ "*" ];
          deny = [ "canvas" ];
          elevated.enabled = true;
          profile = "coding";
        };
        workspace = "~/.openclaw/workspace";
      }
    ];

    # ── Default model config ───────────────────────────────────────
    agents.defaults.model = {
      primary = lib.mkDefault models.OPUS;
      fallbacks = lib.mkDefault [ models.SONNET "openai/gpt-5.4" ];
    };

    # ── TTS ────────────────────────────────────────────────────────
    messages.tts = {
      auto = lib.mkDefault "always";
      provider = lib.mkDefault "elevenlabs";
      mode = lib.mkDefault "final";
      maxTextLength = lib.mkDefault 4000;
      modelOverrides.enabled = lib.mkDefault true;
      openai = {
        model = lib.mkDefault "gpt-4o-mini-tts";
        voice = lib.mkDefault "alloy";
      };
      elevenlabs = {
        modelId = lib.mkDefault "eleven_multilingual_v2";
        voiceSettings = {
          stability = lib.mkDefault 0.5;
          similarityBoost = lib.mkDefault 0.75;
          speed = lib.mkDefault 1;
        };
      };
      summaryModel = lib.mkDefault "openai/gpt-4.1-mini";
    };

    # ── Plugins ────────────────────────────────────────────────────
    # Channel plugins — enable the ones you use. Set tokens in your config.
    plugins.allow = lib.mkDefault [
      "slack"
      "telegram"
      "bluebubbles"
      "voice-call"
      "acpx"
    ];
    plugins.entries = {
      slack = { enabled = lib.mkDefault true; };
      telegram = { enabled = lib.mkDefault true; };
      bluebubbles = { enabled = lib.mkDefault true; };
    };

    # ── Channel bindings ───────────────────────────────────────────
    # Route channels to specific agents.
    bindings = lib.mkDefault [
      { agentId = "assistant"; match = { channel = "bluebubbles"; accountId = "default"; }; }
      { agentId = "main"; match = { channel = "telegram"; accountId = "default"; }; }
    ];

    # ── CLI ────────────────────────────────────────────────────────
    cli.banner.taglineMode = lib.mkDefault "random";

    # ── Commands ───────────────────────────────────────────────────
    commands = {
      bash = lib.mkDefault true;
      native = lib.mkDefault true;
      nativeSkills = lib.mkDefault true;
      restart = lib.mkDefault true;
      text = lib.mkDefault true;
    };
  };
}

# Preset: minimal
# Single agent, basic tools, no channel plugins.
# Good starting point — add what you need.
{ lib, ... }:

{
  programs.openclaw.instances.default.config = {
    agents.list = lib.mkDefault [
      {
        id = "main";
        name = "Main Agent";
        default = true;
        agentDir = "~/.openclaw/agents/main/agent";
        model = "anthropic/claude-sonnet-4-6";
        identity = { emoji = "🦞"; name = "OpenClaw"; theme = "ayu"; };
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
    ];
  };
}

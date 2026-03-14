# Preset: developer
# Main agent + dedicated coding agent. ACP enabled for Volt VMs.
# Good for solo developers who want a coding assistant.
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
      {
        id = "coder";
        name = "Coding Agent";
        default = false;
        agentDir = "~/.openclaw/agents/coder/agent";
        model = "anthropic/claude-sonnet-4-6";
        identity = { emoji = "⚡"; name = "Volt"; theme = "ayu"; };
        sandbox.mode = "off";
        subagents.allowAgents = [ "main" ];
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

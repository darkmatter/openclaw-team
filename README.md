# Dark Matter OpenClaw Team Config

Private repo for the Dark Matter team. Add this as a flake input to your nix-darwin repo to get a fully configured OpenClaw setup with shared secrets and access to Volt coding VMs.

## Setup

### 1. Add to your flake inputs

```nix
# Private repo — use SSH URL
inputs.openclaw-team = {
  url = "git+ssh://git@github.com/darkmatter/openclaw-team.git";
  inputs.nixpkgs.follows = "nixpkgs";
};

# Also need sops-nix for secrets
inputs.sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Import the modules

In your home-manager imports:

```nix
imports = [
  inputs.nix-openclaw.homeManagerModules.openclaw
  inputs.sops-nix.homeManagerModules.sops
  inputs.openclaw-team.homeManagerModules.default
];
```

### 3. Enroll

From a clone of this repo:

```bash
./scripts/enroll <your-github-username>
```

This:
1. Reads your host's age key (from `/etc/ssh/ssh_host_ed25519_key`, or auto-generates one)
2. Fetches your SSH keys from `github.com/<username>.keys` and converts to age
3. Writes `keys/<username>.txt`
4. Regenerates `.sops.yaml`
5. Commits and pushes

**GitHub Actions** automatically re-encrypts all secrets with the new key. Wait for the action to complete, then pull.

### 4. Configure

```nix
openclaw-dm = {
  enable = true;
  tailscaleMachineName = "my-macbook";  # your Tailscale hostname
};
```

That's it. Override any OpenClaw setting directly:

```nix
# Team module sets sensible defaults with lib.mkDefault.
# Override anything via programs.openclaw:
programs.openclaw.instances.default.config = {
  agents.defaults.model.primary = "anthropic/claude-opus-4-6";
  # ... any openclaw config field
};
```

### 5. Pick a preset (optional)

Presets give you a pre-built agent + config setup. Import one alongside the team module:

```nix
imports = [
  inputs.openclaw-team.homeManagerModules.default
  inputs.openclaw-team.presets.developer    # or: minimal, multi-agent
];
```

| Preset | Agents | What it sets |
|--------|--------|--------------|
| `minimal` | main | Single agent, basic tools. Clean starting point. |
| `developer` | main + coder | Coding agent pair. Good for solo devs. |
| `multi-agent` | main + assistant + coder | Channel routing, TTS, messaging plugins. Full setup. |

All preset values use `lib.mkDefault` — override anything in your own config:

```nix
# Use developer preset but switch to opus
programs.openclaw.instances.default.config.agents.defaults.model.primary = "anthropic/claude-opus-4-6";
```

### 6. Multi-machine

```nix
# Desktop (always-on, runs the gateway)
openclaw-dm = {
  enable = true;
  tailscaleMachineName = "my-desktop";
  role = "primary";
};

# Laptop (connects to desktop's gateway)
openclaw-dm = {
  enable = true;
  tailscaleMachineName = "my-laptop";
  role = "remote-personal";
  primaryHost = "my-desktop";
};

# Headless server
openclaw-dm = {
  enable = true;
  tailscaleMachineName = "my-server";
  role = "remote-server";
  primaryHost = "my-desktop";
};
```

### 7. Apply

```bash
darwin-rebuild switch --flake .
```

## What You Get

- **Gateway config** — Tailscale Funnel, password auth, auto-configured
- **ACP access to Volt VMs** — `volt-1` through `volt-4` (64 cores, 128GB RAM)
- **acpx config** — auto-written to `~/.acpx/config.json`
- **Auto-decrypted secrets** — API keys (Anthropic, OpenAI, OpenRouter), gateway password, Volt token
- **SSH host key → age** — auto-persisted at activation for sops CLI usage

## Enrolling a Team Member

```bash
./scripts/enroll <github-username> [key-label]
```

The enrollment script collects age public keys and pushes to the repo. **GitHub Actions handles the rest** — the `update-keys` workflow:

1. Triggers on any push that changes `.sops.yaml`
2. Decrypts all secrets using the GitHub Actions age key
3. Re-encrypts with the updated key list
4. Commits the re-encrypted files

The new member just needs to `git pull` after the action completes, then `darwin-rebuild switch`.

### Manual key rotation

If you need to re-encrypt outside of enrollment:

```bash
# Edit .sops.yaml manually, then:
git add .sops.yaml && git commit -m "update keys" && git push
# GitHub Actions will re-encrypt automatically
```

## Shared Workspace (Google Drive)

Syncs a `shared/` subdirectory via Google Drive using a service account — **no per-user setup needed**.

```nix
openclaw-dm.sharedWorkspace.enable = true;
```

Uses the `darkmatter` Shared Drive. Service account key is sops-encrypted. rclone is auto-configured at activation.

```
~/.openclaw/workspace/
├── shared/              ← GDrive-synced across team
│   ├── skills/
│   ├── team-wiki/
│   └── memory/
├── IDENTITY.md          ← personal
├── USER.md              ← personal
├── SOUL.md              ← personal
└── HEARTBEAT.md         ← personal
```

## Options

The `openclaw-dm` namespace controls **team infrastructure only**. All OpenClaw config is set via `programs.openclaw` (with `lib.mkDefault` so you can override anything).

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable team infrastructure |
| `tailscaleMachineName` | required | Your Tailscale hostname |
| `role` | `"primary"` | `"primary"` / `"remote-personal"` / `"remote-server"` |
| `primaryHost` | `""` | Primary's Tailscale name (required for remote roles) |
| `manageSopsSecrets` | `true` | Auto-configure sops-nix for team secrets |
| `sharedWorkspace.enable` | `false` | Enable GDrive workspace sync |
| `sharedWorkspace.interval` | `"5m"` | Sync interval |
| `sharedWorkspace.direction` | `"bisync"` | `bisync` / `pull` / `push` |

## Secrets

All secrets are sops-encrypted (one per file) and auto-decrypted by sops-nix at activation:

| Secret | File | Used for |
|--------|------|----------|
| Gateway password | `secrets/gateway-password.yaml` | OpenClaw gateway auth |
| Volt password | `secrets/volt-gateway-password.yaml` | ACP access to Volt VMs |
| Anthropic API key | `secrets/anthropic-api-key.yaml` | LLM provider |
| OpenAI API key | `secrets/openai-api-key.yaml` | LLM provider |
| OpenRouter API key | `secrets/openrouter-api-key.yaml` | LLM provider |
| GDrive SA key | `secrets/gdrive-sa-key.yaml` | Shared workspace sync |

Key rotation is handled by GitHub Actions — just update `.sops.yaml` and push.

## Architecture

```
┌─────────────────────────┐    ┌─────────────────────────┐
│ Alice's Mac (primary)   │    │ Bob's Mac (primary)     │
│ wss://alice.ts.net      │    │ wss://bob.ts.net        │
│ ┌─────────────────────┐ │    │ ┌─────────────────────┐ │
│ │ OpenClaw Gateway    │ │    │ │ OpenClaw Gateway    │ │
│ └─────────┬───────────┘ │    │ └─────────┬───────────┘ │
│           │ ACP         │    │           │ ACP         │
└───────────┼─────────────┘    └───────────┼─────────────┘
            │                              │
            ▼                              ▼
   ┌─────────────────────────────────────────────┐
   │  Shared Volt VMs (Hetzner runner)           │
   │  volt-1..4.tail6277a6.ts.net                │
   │  64 cores / 128GB RAM                       │
   └─────────────────────────────────────────────┘
```

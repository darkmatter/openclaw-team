# Dark Matter OpenClaw Team Config

Private repo for the Dark Matter team. Add this as a flake input to your nix-darwin repo to get a fully configured OpenClaw setup that connects to our Volt coding VMs.

## Setup

### 1. Add to your flake inputs

```nix
inputs.openclaw-team = {
  url = "github:darkmatter/openclaw-team";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Import the module

In your home-manager config:

```nix
imports = [ inputs.openclaw-team.homeManagerModules.default ];
```

### 3. Configure

```nix
openclaw-dm = {
  enable = true;
  tailscaleMachineName = "my-macbook";  # your Tailscale hostname

  # role = "primary" by default — runs gateway with Tailscale Funnel
  # model = "anthropic/claude-opus-4-6";  # optional, default: sonnet
};
```

For a multi-machine setup (e.g. desktop + laptop):

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

### 4. Set up your age key

You need an age identity that's listed in `.sops.yaml` so sops-nix can decrypt secrets at activation time.

**If you already have an age key** (e.g. `~/.config/sops/age/keys.txt`), give Cooper your public key to add to `.sops.yaml`.

**If you don't have one yet:**

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Give Cooper the public key line from the output
```

Once your key is in `.sops.yaml`, the GitHub Action will automatically re-encrypt all secrets so you can decrypt them.

### 5. Apply

```bash
darwin-rebuild switch --flake .
```

## What You Get

- **Main agent** — your primary AI assistant
- **Coder agent** — dedicated coding agent
- **ACP access to Volt VMs** — `volt-1` through `volt-4` on our Hetzner runner (64 cores, 128GB RAM)
- **Gateway config** — each member runs their own primary gateway via Tailscale Funnel
- **acpx config** — automatically written to `~/.acpx/config.json`
- **Auto-decrypted secrets** — gateway password and Volt token via sops-nix (no manual token files)

## Shared Workspace

Team members can sync a `shared/` subdirectory in their OpenClaw workspace via rclone. This is useful for shared skills, team wiki, memory, and tool notes.

```nix
openclaw-dm = {
  enable = true;
  # ...

  sharedWorkspace = {
    enable = true;
    remote = "s3:darkmatter-openclaw/shared";  # or dropbox:, gdrive:, etc.
    interval = "5m";       # sync every 5 minutes
    direction = "bisync";  # two-way sync (default)
  };
};
```

Configure the rclone remote first: `rclone config`

**Workspace layout:**

```
~/.openclaw/workspace/
├── shared/              ← rclone-synced across team
│   ├── skills/          ← team skills
│   ├── team-wiki/       ← shared knowledge base
│   ├── memory/          ← team memory
│   └── TOOLS.md         ← shared tool notes
├── IDENTITY.md          ← personal (your agent's name/emoji)
├── USER.md              ← personal (about you)
├── SOUL.md              ← personal (agent personality)
└── HEARTBEAT.md         ← personal (background tasks)
```

## Adding a Team Member

1. Get their age public key (or SSH ed25519 public key)
2. Add it to `.sops.yaml` under `keys:` and in `creation_rules`
3. Commit and push — the GitHub Action re-encrypts all secrets automatically
4. They pull, run `darwin-rebuild switch`, done

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable OpenClaw |
| `hostId` | required | Your machine identifier |
| `tailscaleMachineName` | required | Your Tailscale hostname (from `tailscale status`) |
| `role` | `"primary"` | `"primary"`, `"remote-personal"`, or `"remote-server"` |
| `primaryHost` | `""` | Tailscale name of your primary (required for remote roles) |
| `model` | `claude-sonnet-4-6` | Default model |
| `enableCoder` | `true` | Include the coder agent |
| `secrets.passwordPath` | `null` | Path to gateway password file |
| `secrets.tokenPath` | `null` | Path to gateway token file |
| `secrets.voltPasswordPath` | `null` | Path to Volt VM password |
| `extraConfig` | `{}` | Merge extra config into openclaw.json |

## Architecture

Each team member runs their own OpenClaw gateway with Tailscale Funnel. Everyone shares access to the Volt coding VMs.

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

For multi-machine users (e.g. desktop + laptop):

```
Desktop (primary)  ◄── Laptop (remote)
wss://desktop.ts.net    connects via Tailscale
```

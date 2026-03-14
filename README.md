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
  hostId = "your-machine-name";

  # Point to your decrypted gateway password
  secrets.passwordPath = "/run/agenix/openclaw-gateway-password";

  # Optional: use a specific model (default: claude-sonnet-4-6)
  # model = "anthropic/claude-opus-4-6";
};
```

### 4. Save the Volt password

The Volt VM password needs to be at `~/.config/volt/token`. Ask Cooper for the value, then:

```bash
mkdir -p ~/.config/volt
echo -n '<password>' > ~/.config/volt/token
chmod 600 ~/.config/volt/token
```

Or manage it with agenix/sops-nix and symlink it.

### 5. Apply

```bash
darwin-rebuild switch --flake .
```

## What You Get

- **Main agent** — your primary AI assistant
- **Coder agent** — dedicated coding agent
- **ACP access to Volt VMs** — `volt-1` through `volt-4` on our Hetzner runner (64 cores, 128GB RAM)
- **Pre-configured gateway** — connects to Cooper's Mac Studio via Tailscale Funnel
- **acpx config** — automatically written to `~/.acpx/config.json`

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable OpenClaw |
| `hostId` | required | Your machine identifier |
| `role` | `"remote"` | `"remote"` for team members, `"primary"` for Cooper's Mac Studio |
| `model` | `claude-sonnet-4-6` | Default model |
| `enableCoder` | `true` | Include the coder agent |
| `secrets.passwordPath` | `null` | Path to gateway password file |
| `secrets.tokenPath` | `null` | Path to gateway token file |
| `secrets.voltPasswordPath` | `null` | Path to Volt VM password |
| `extraConfig` | `{}` | Merge extra config into openclaw.json |

## Architecture

```
Cooper's Mac Studio (primary gateway)
  └── Tailscale Funnel → wss://coopers-mac-studio.tail6277a6.ts.net
        ├── Your MacBook (remote) ←── this module
        ├── Other team members (remote)
        └── Volt VMs (ACP agents)
              ├── volt-1.tail6277a6.ts.net
              ├── volt-2.tail6277a6.ts.net
              ├── volt-3.tail6277a6.ts.net
              └── volt-4.tail6277a6.ts.net
```

{
  description = "Dark Matter OpenClaw team config — add as input to your nix-darwin repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    openclaw-nix = {
      url = "github:darkmatter/openclaw.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, openclaw-nix, agenix, sops-nix, ... }: {
    # Home-manager module — import this in your darwin config
    homeManagerModules.default = ./modules/team.nix;

    # Re-export for convenience
    overlays.default = openclaw-nix.overlays.default;
    nixosModules = openclaw-nix.nixosModules;
  };
}

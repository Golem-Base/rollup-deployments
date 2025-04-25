{
  description = "op.nix / Optimism dev environment with Nix!";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    devshell.url = "github:numtide/devshell";

    foundry.url = "github:shazow/foundry.nix/stable";

    sops = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    solc = {
      url = "github:hellwolf/solc.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      debug = true;

      imports = [
        inputs.devshell.flakeModule
        inputs.treefmt-nix.flakeModule
        ./nix/shell.nix
        ./nix/formatter.nix
        ./nix/packages
      ];

      systems = [ "x86_64-linux" ];
      perSystem =
        { system, ... }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              inputs.foundry.overlay
              inputs.solc.overlay
            ];
          };
        };
    };
}

_: {
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        # packages = (with pkgs; [
        #     foundry-bin
        #     sops
        #     alejandra
        #   ]) ++ (with self'.packages; [
        #     op-deployer
        #   ]);

        # env = [
        #   {
        #     name = "NIX_PATH";
        #     value = "nixpkgs=${toString pkgs.path}";
        #   }
        #   {
        #     name = "NIX_DIR";
        #     eval = "$PRJ_ROOT/nix";
        #   }
        # ];
      };
    };
}

# { pkgs, perSystem }:
# perSystem.devshell.mkShell {
#   packages = [
#     perSystem.self.formatter
#     pkgs.just
#   ];

#   commands = [
#   ];
# }

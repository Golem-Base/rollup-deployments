_: {
  perSystem =
    {
      self',
      pkgs,
      ...
    }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages =
          (with pkgs; [
            foundry-bin
            sops
            alejandra
          ])
          ++ (with self'.packages; [
            op-deployer
          ]);
      };
    };
}

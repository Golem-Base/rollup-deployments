_: {
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        packages = (with pkgs; [
            foundry-bin
            just
          ]) ++ (with self'.packages; [
            op-deployer
          ]) ++ [self'.formatter];
      };
    };
}

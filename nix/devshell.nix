_: {
  perSystem = {
    pkgs,
    self',
    inputs',
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        foundry-bin
        just
        alejandra

        self'.packages.op-deployer
        self'.formatter
        inputs'.sops.packages.default
      ];
    };
  };
}

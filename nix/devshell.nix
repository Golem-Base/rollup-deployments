_: {
  perSystem = {
    pkgs,
    self',
    inputs',
    ...
  }: {
    devshells.default = {
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

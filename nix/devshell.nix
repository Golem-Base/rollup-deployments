_: {
  perSystem = {
    pkgs,
    self',
    ...
  }: {
    devshells.default = {
      packages = with pkgs; [
        foundry-bin
        just
        alejandra
        sops
        ssh-to-age
        age
        diceware

        self'.packages.gb-deployer
        self'.packages.op-deployer
        self'.packages.op-geth

        self'.formatter
      ];
      env = [
        {
          name = "SOPS_CONFIG";
          eval = "$PRJ_ROOT/sops/config.yaml";
        }
        {
          name = "SOPS_SECRETS";
          eval = "$PRJ_ROOT/sops/secrets.json";
        }
      ];
    };
  };
}

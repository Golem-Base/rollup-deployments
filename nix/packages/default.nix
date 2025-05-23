{lib, ...}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: let
    inherit (pkgs) callPackage;
  in {
    packages = rec {
      # TODO v3.0.0 needs work
      # contracts-bedrock-v3_0_0-rc2 = callPackage ./contracts-bedrock/v3.0.0-rc.2 { };
      contracts-bedrock-v2_0_0-rc1 = callPackage ./contracts-bedrock/v2.0.0-rc.1 {};
      contracts-bedrock-v1_7_0-beta_1_l2-contracts =
        callPackage ./contracts-bedrock/v1.7.0-beta.1+l2-contracts
        {};

      op-deployer-v0_2_0-rc2 = callPackage ./op-deployer/v0.2.0-rc.2 {};

      # renamed to gb-deployer to allow having multiple op-deployer in packages without conflicts
      gb-deployer = callPackage ./op-deployer/v0.2.0-rc.2-gb {};

      op-deployer = gb-deployer;
      op-geth = callPackage ./op-geth/v1.101503.1 {};

      init-rollup = callPackage ./init-rollup.nix {inherit op-deployer select-rollup;};
      select-rollup = callPackage ./select-rollup.nix {};
      delete-rollup = callPackage ./delete-rollup.nix {inherit select-rollup;};
      fund-rollup = callPackage ./fund-rollup.nix {inherit select-rollup;};
      deploy-rollup = callPackage ./deploy-rollup.nix {inherit op-deployer select-rollup;};
      upload-rollup = callPackage ./upload-rollup.nix {inherit select-rollup;};
    };

    apps =
      lib.mapAttrs
      (_name: package: {
        type = "app";
        program = lib.getExe package;
      })
      (
        lib.filterAttrs (
          _name: package: lib.isDerivation package && package ? meta.mainProgram
        )
        self'.packages
      );
  };
}

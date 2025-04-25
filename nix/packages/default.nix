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
      op-deployer-v0_2_0-rc2 = callPackage ./op-deployer/op-deployer-v0.2.0-rc.2.nix {};

      op-deployer = op-deployer-v0_2_0-rc2;
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

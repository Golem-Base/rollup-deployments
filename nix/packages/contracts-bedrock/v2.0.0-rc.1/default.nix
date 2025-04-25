{
  pkgs,
  lib,
  fetchFromGitHub,
  ...
}: let
  mkSolcSvmInstallation = solcPkg: let
    solcBinPath = lib.getExe solcPkg;
    version = lib.lists.last (
      lib.strings.splitString "-" (lib.lists.last (lib.splitString "/" solcBinPath))
    );
  in ''
    mkdir -p $XDG_DATA_HOME/svm/${version}
    ln -s ${solcBinPath} $XDG_DATA_HOME/svm/${version}/solc-${version}
  '';

  mkSolcSvmDataDir = solcPkgs: let
    solcInstalls = lib.strings.concatLines (lib.lists.forEach solcPkgs mkSolcSvmInstallation);
  in ''
    export XDG_DATA_HOME=$(mktemp -d)
    mkdir -p $XDG_DATA_HOME/svm
    touch $XDG_DATA_HOME/svm/.global-version
    ${solcInstalls}
  '';
in
  pkgs.stdenv.mkDerivation {
    pname = "contracts-bedrock";
    version = "v2.0.0-rc.1";

    src = fetchFromGitHub {
      owner = "ethereum-optimism";
      repo = "optimism";
      rev = "8d0dd96e494b2ba154587877351e87788336a4ec";
      hash = "sha256-alsWwj6bb3QkhakED8a9hBF9RE98HQRYmRtNTYhrpjA=";
      fetchSubmodules = true;
    };

    nativeBuildInputs = with pkgs; [foundry-bin];

    buildPhase = ''
      cp $src/packages/contracts-bedrock/foundry.toml .
      cp -r $src/packages/contracts-bedrock/src .
      cp -r $src/packages/contracts-bedrock/interfaces .
      cp -r $src/packages/contracts-bedrock/test .
      cp -r $src/packages/contracts-bedrock/scripts .
      cp -r $src/packages/contracts-bedrock/lib .

      ${mkSolcSvmDataDir (
        with pkgs; [
          solc_0_8_15
          solc_0_8_19
          solc_0_8_25
          solc_0_8_28
        ]
      )}

      forge build --offline
    '';

    installPhase = ''
      mkdir -p $out
      cp -r forge-artifacts $out/
      cp -r artifacts $out/
      cp -r cache $out/
      echo ef7a933ca7f3d27ac40406f87fea25e0c3ba2016 > $out/COMMIT
    '';

    meta = with lib; {
      description = "Optimism is Ethereum, scaled.";
      homepage = "https://optimism.io/";
      license = with licenses; [mit];
      platforms = ["x86_64-linux"];
    };
  }

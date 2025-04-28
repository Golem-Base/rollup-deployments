{
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "op-deployer";
  version = "0.2.0-rc.2";

  src = fetchFromGitHub {
    owner = "ethereum-optimism";
    repo = "optimism";
    rev = "op-deployer/v${version}";
    hash = "sha256-OpJCAkFpZuCysXpzRnWXvq3N0f3oBQrLfCpxx83yuYo=";
  };

  patches = [
    ./chain_id_2345.patch
    ./debug.patch
  ];

  vendorHash = "sha256-/jW5EPRGjUi5ZrOBS08bXfP0x1KHFgelY7WseDvGzFM=";

  doCheck = false;

  subPackages = ["op-deployer/cmd/op-deployer"];

  meta.mainProgram = "op-deployer";
}

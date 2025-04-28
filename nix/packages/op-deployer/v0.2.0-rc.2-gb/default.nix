# This fork adds a flag to specify the suprechain proxy admin. Upstream
# hard-codes that address for mainnet and sepolia only.
{buildGoModule}:
buildGoModule rec {
  pname = "op-deployer";
  version = "gb/op-deployer/v0.2.0-rc.2";

  src = builtins.fetchGit {
    url = "git@github.com:Golem-Base/optimism";
    ref = version;
    rev = "70f9eb30a3aeb8715b1620802a0d82b3c04bb884";
  };

  vendorHash = "sha256-/jW5EPRGjUi5ZrOBS08bXfP0x1KHFgelY7WseDvGzFM=";

  subPackages = ["op-deployer/cmd/op-deployer"];

  postInstall = ''
    mv $out/bin/op-deployer $out/bin/gb-deployer
  '';

  meta.mainProgram = "gb-deployer";
}

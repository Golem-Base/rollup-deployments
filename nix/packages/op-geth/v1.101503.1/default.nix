{
  go-ethereum,
  fetchFromGitHub,
}:
go-ethereum.overrideAttrs (
  final: _prev: {
    name = "op-geth";

    src = fetchFromGitHub {
      owner = "ethereum-optimism";
      repo = final.name;
      rev = "v1.101503.1";
      hash = "sha256-6PS6vUy91Z5ryS6xLltvvwCuStBPrFv9E3T+WW0miU8=";
    };

    vendorHash = "sha256-L0zL+iHFYxPXbfT76M3jYIPAaokDauDLzj3MI4V/76M=";

    subPackages = [
      "cmd/abidump"
      "cmd/abigen"
      "cmd/blsync"
      "cmd/clef"
      "cmd/devp2p"
      "cmd/era"
      "cmd/ethkey"
      "cmd/evm"
      "cmd/geth"
      "cmd/rlpdump"
      "cmd/utils"
    ];
  }
)

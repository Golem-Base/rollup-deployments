_: {
  perSystem = {
    pkgs,
    self',
    ...
  }: let
    el-rpc = pkgs.writeShellScriptBin "el-rpc" ''
      # Define the RPC command and jq filter from arguments
      rpc_cmd=$1
      jq_filter=$2
      nodes="PYX ZAS ELK KEX AVO URB"
      temp_file=$(mktemp)
      for node in $nodes; do
        (
          node_var="''${node}_EXECUTION_RPC"
          rpc_url=$(printenv "$node_var")
          result=$(cast rpc $rpc_cmd --rpc-url "$rpc_url" --json | jq "$jq_filter" 2>/dev/null || echo "ERROR")
          echo "$node $result" >> "$temp_file"
        ) &
      done
      wait
      sort "$temp_file" | column -t
      rm "$temp_file"
    '';

    cl-rpc = pkgs.writeShellScriptBin "cl-rpc" ''
      rpc_cmd=$1
      jq_filter=$2
      nodes="PYX ZAS ELK KEX AVO URB"
      temp_file=$(mktemp)
      for node in $nodes; do
        (
          node_var="''${node}_CONSENSUS_RPC"
          rpc_url=$(printenv "$node_var")
          result=$(cast rpc $rpc_cmd --rpc-url "$rpc_url" --json | jq "$jq_filter" 2>/dev/null || echo "ERROR")
          echo "$node $result" >> "$temp_file"
        ) &
      done
      wait
      sort "$temp_file" | column -t
      rm "$temp_file"
    '';
  in {
    devshells.default = {
      packages = with pkgs; [
        age
        alejandra
        dasel
        diceware
        foundry-bin
        just
        minio-client
        sops
        ssh-to-age

        minio-client
        doppler

        docker
        el-rpc
        cl-rpc

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

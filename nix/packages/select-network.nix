{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellScriptBin "select-network" ''
  #!/usr/bin/env bash
  set -euo pipefail

  # Configuration
  PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
  CHAIN_IDS_FILE="''${CHAIN_IDS_FILE:-$PRJ_ROOT/deployments/chain-ids.json}"

  SHOW_FULL_PATH=false
  SKIP_L1=false
  SKIP_L3=false
  for arg in "$@"; do
    case "$arg" in
      --skip-l3)
        SKIP_L3=true
        ;;
    esac
    case "$arg" in
      --skip-l1)
        SKIP_L1=true
        ;;
    esac
    case "$arg" in
      --show-full-path)
        SHOW_FULL_PATH=true
        ;;
    esac
  done
  # Check if chain-ids.json exists
  if [ ! -f "$CHAIN_IDS_FILE" ]; then
      echo "Error: chain-ids.json not found at $CHAIN_IDS_FILE"
      exit 1
  fi

  l1_networks=$(${lib.getExe pkgs.jq} 'keys | join(" ")' $CHAIN_IDS_FILE | tr -d '"')
  networks_list=""
  for l1_network in $l1_networks; do
    if [ "$SKIP_L1" = false ]; then
      networks_list+="$l1_network\n"
    fi
    l1_network_data=$(${lib.getExe pkgs.jq} --arg l1 "$l1_network" '.[$l1]' $CHAIN_IDS_FILE)
    if [ -z "$l1_network_data" ] || [ "$l1_network_data" == null ]; then
      continue
    fi
    l2_networks=$(echo $(${lib.getExe pkgs.jq} 'with_entries(select(.key != "id")) | keys | join(" ")' <<<$l1_network_data) | tr -d '"')
    for l2_network in $l2_networks; do
      networks_list+="$l1_network/$l2_network\n"
      if [ "$SKIP_L3" = true ]; then
        continue
      fi

      l2_network_data=$(${lib.getExe pkgs.jq} --arg l1 "$l1_network" --arg l2 "$l2_network" '.[$l1][$l2]' $CHAIN_IDS_FILE)
      l3_networks=$(echo $(${lib.getExe pkgs.jq} 'with_entries(select(.key != "id" and .key != "created_at")) | keys | join(" ")' <<<$l2_network_data) | tr -d '"')
      for l3_network in $l3_networks; do
        networks_list+="$l1_network/$l2_network/$l3_network\n"
      done
    done
  done
  selected=$(echo -e "$networks_list" | fzf --ansi --height=40% --reverse --header="Select a network")

  if [ "$SHOW_FULL_PATH" = true ]; then
    echo "$selected"
  else
    echo "$selected" | rev | cut -d/ -f1 | rev
  fi
''

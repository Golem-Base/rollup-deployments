rpc_url := env("ETH_RPC_URL")
sepolia_chain_id := "11155111"
holesky_chain_id := "17000"
mainnet_chain_id := "1"
deployments_dir := env_var_or_default("PRJ_DATA", ".") + "/deployments"
chain_ids_file := deployments_dir + "/chain-ids.json"

# List of known L1 networks
l1_networks := {
    "1": "mainnet",
    "11155111": "sepolia",
    "17000": "holesky"
}

default:
    @just --list

# Initialize the chain-ids.json file if it doesn't exist
init-chain-ids:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Create deployments directory if it doesn't exist
    mkdir -p "{{deployments_dir}}"
    
    # Check if chain-ids.json exists
    if [ ! -f "{{chain_ids_file}}" ]; then
        # Create initial structure with L1 networks
        cat > "{{chain_ids_file}}" << EOF
[
  {
    "name": "mainnet",
    "chain-id": 1,
    "rollups": []
  },
  {
    "name": "sepolia",
    "chain-id": 11155111,
    "rollups": []
  },
  {
    "name": "holesky",
    "chain-id": 17000,
    "rollups": []
  }
]
EOF
        echo "Created initial chain-ids.json file"
    else
        echo "chain-ids.json already exists"
    fi

# Generate a network name and ID
gen-network-name-id:
    #!/usr/bin/env bash
    name=$(diceware -n 1 -w "en_adjectives")$(diceware -n 1 -w "en_nouns")
    full_hash=$(cast keccak "$name")
    id=$((16#${full_hash:2:6}))
    echo "$name $id"

# Find a network in the chain-ids.json file by chain ID
find-network chain_id:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Make sure chain-ids.json exists
    if [ ! -f {{chain_ids_file}}" ]; then
        just init-chain-ids
    fi
    
    # Find the network in the chain-ids.json file
    # This function recursively searches the JSON structure using jq
    find_result=$(jq -r --arg chain_id "{{chain_id}}" '
      # Recursive function to find a path to an object with the given chain-id
      def find_path($id; $current_path):
        # Check if current object has the chain-id
        if .["chain-id"] == ($id | tonumber) then
          $current_path
        # If it has rollups, search them
        elif .rollups then
          # Try each rollup
          [.rollups[] | . as $child | 
            ($current_path + "/" + $child.name) as $new_path |
            find_path($id; $new_path)] | 
          # Return the first non-empty result
          map(select(length > 0)) | if length > 0 then .[0] else "" end
        else
          ""
        end;
      
      # Apply to each top-level network
      [.[] | . as $network | 
        $network.name as $name |
        find_path($chain_id; $name)] |
      # Return the first non-empty result
      map(select(length > 0)) | if length > 0 then .[0] else "" end
    ' "{{chain_ids_file}}")
    
    if [ -n "$find_result" ]; then
        echo "$find_result"
        exit 0
    else
        echo "unknown-network-{{chain_id}}"
        exit 1
    fi

# Get the network path based on chain ID
get-network:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Get chain ID using cast
    chain_id=$(cast chain-id --rpc-url {{rpc_url}})
    
    just find-network $chain_id

# Update chain-ids.json by adding a new rollup
add-rollup parent_path name chain_id:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Make sure chain-ids.json exists
    if [ ! -f "{{chain_ids_file}}" ]; then
        just init-chain-ids
    fi
    
    # Parse the parent path to get the components
    IFS="/" read -ra path_components <<< "{{parent_path}}"
    
    # Build the jq filter
    jq_filter='
    # Convert chain ID to number
    $chain_id | tonumber as $chain_id_num |
    
    # Function to check if a chain ID already exists
    def chain_id_exists($id):
      walk(if type == "object" and has("chain-id") and .["chain-id"] == $id then true else . end) | 
      contains(true);
    
    # Check if chain ID already exists
    if chain_id_exists($chain_id_num) then
      "chain-id-exists"
    else
      # Main update function
      def update_at_path($components; $idx; $name; $chain_id):
        # Base case: if we reached the end of components, add the new rollup
        if $idx >= ($components | length) then
          .rollups += [{
            "name": $name,
            "chain-id": $chain_id,
            "rollups": []
          }]
        # Recursive case: navigate to the next component
        else
          # Get the current component
          $components[$idx] as $current |
          
          # Find the index of the current component in rollups
          (.rollups | map(.name == $current) | index(true)) as $rollup_idx |
          
          # If component exists in rollups, update that rollup
          if $rollup_idx != null then
            .rollups[$rollup_idx] |= update_at_path($components; $idx + 1; $name; $chain_id)
          # If at the top level, check main networks
          elif $idx == 0 then
            "invalid-path"
          else
            "invalid-path"
          end
        end;
      
      # Start with empty components for the "all" case
      [] as $components |
    
      if {{parent_path | tojson}} == "all" then
        # Adding directly to root
        . += [{
          "name": $name,
          "chain-id": $chain_id_num,
          "rollups": []
        }]
      else
        # Regular path
        {{parent_path | split("/") | tojson}} as $path_components |
        
        # Find the top-level network
        map(
          if .name == $path_components[0] then
            # Found the top-level network, now update it
            update_at_path($path_components; 1; $name; $chain_id_num)
          else
            .
          end
        )
      end
    end
    '
    
    # Apply the filter
    result=$(jq --arg name "{{name}}" --arg chain_id "{{chain_id}}" "$jq_filter" "{{chain_ids_file}}")
    
    # Check for special result codes
    if [ "$result" = "\"chain-id-exists\"" ]; then
        echo "❌ Error: Chain ID {{chain_id}} already exists in chain-ids.json"
        exit 1
    elif [ "$result" = "\"invalid-path\"" ]; then
        echo "❌ Error: Invalid path {{parent_path}}"
        exit 1
    else
        # Update the file
        echo "$result" > "{{chain_ids_file}}"
        echo "Updated chain-ids.json: Added {{name}} ({{chain_id}}) to {{parent_path}}"
    fi

# Set up a deployment directory for the current network
setup-deployment-dir name="":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Make sure chain-ids.json exists
    if [ ! -f "{{chain_ids_file}}" ]; then
        just init-chain-ids
    fi
    
    # Get current chain ID
    chain_id=$(cast chain-id --rpc-url {{rpc_url}})
    
    # Use provided name or generate one
    deployment_name="{{name}}"
    if [ -z "$deployment_name" ]; then
        name_and_id=$(just gen-network-name-id)
        deployment_name=$(echo "$name_and_id" | cut -d' ' -f1)
    fi
    
    # Check if it's a known L1
    if [[ -n "{{l1_networks[$chain_id]:-}}" ]]; then
        # We're deploying directly on an L1
        l1="{{l1_networks[$chain_id]}}"
        
        # Create the L1 directory if it doesn't exist
        l1_dir="{{deployments_dir}}/$l1"
        mkdir -p "$l1_dir"
        
        # Check if the deployment directory already exists
        deployment_dir="$l1_dir/$deployment_name"
        if [ -d "$deployment_dir" ]; then
            echo "❌ Error: Deployment directory $deployment_dir already exists"
            exit 1
        fi
        
        # Create deployment directory
        mkdir -p "$deployment_dir"
        
        # Generate a chain ID for this L2 if not provided
        if [ -z "{{name}}" ]; then
            l2_chain_id=$(echo "$name_and_id" | cut -d' ' -f2)
        else
            l2_chain_id=$((16#$(cast keccak "{{name}}" | cut -c 3-8)))
        fi
        
        # Update chain-ids.json
        just add-rollup "$l1" "$deployment_name" "$l2_chain_id"
        
        echo "Created new L2 deployment in L1 ($l1):"
        echo "Directory: $deployment_dir"
        echo "Network Name: $deployment_name"
        echo "Chain ID: $l2_chain_id"
        
    else
        # We're not on an L1, so we need to find the parent chain
        parent_path=""
        
        # Try to get the network path
        parent_path=$(just get-network 2>/dev/null || echo "")
        
        if [ -z "$parent_path" ] || [[ "$parent_path" == unknown-network-* ]]; then
            echo "❌ Error: Cannot find parent chain for chain ID $chain_id"
            echo "You need to connect to an L1 or a known rollup to deploy a new layer"
            exit 1
        fi
        
        echo "Found parent chain: $parent_path"
        
        # Create the deployment directory
        full_path="$parent_path/$deployment_name"
        deployment_dir="{{deployments_dir}}/$full_path"
        
        if [ -d "$deployment_dir" ]; then
            echo "❌ Error: Deployment directory $deployment_dir already exists"
            exit 1
        fi
        
        # Create deployment directory
        mkdir -p "$deployment_dir"
        
        # Generate a chain ID for this new layer if not provided
        if [ -z "{{name}}" ]; then
            new_chain_id=$(echo "$name_and_id" | cut -d' ' -f2)
        else
            new_chain_id=$((16#$(cast keccak "{{name}}" | cut -c 3-8)))
        fi
        
        # Update chain-ids.json
        just add-rollup "$parent_path" "$deployment_name" "$new_chain_id"
        
        echo "Created new deployment under parent chain:"
        echo "Directory: $deployment_dir"
        echo "Network Name: $deployment_name" 
        echo "Chain ID: $new_chain_id"
    fi
    
    # Write a README.md in the deployment directory with basic info
    cat > "$deployment_dir/README.md" << EOF
# $deployment_name Deployment

This directory contains deployment artifacts for the "$deployment_name" rollup.

- **Path:** $(realpath --relative-to="{{deployments_dir}}" "$deployment_dir")
- **Created:** $(date)
EOF
    
    # Return the deployment name
    echo "$deployment_name"

# Pretty-print the chain-ids.json file
show-networks:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Make sure chain-ids.json exists
    if [ ! -f "{{chain_ids_file}}" ]; then
        just init-chain-ids
    fi
    
    # Pretty-print the JSON
    jq '.' "{{chain_ids_file}}"

# Main justfile - Entry point for rollup deployments
# Usage: just <network> <command>
# Example: just holesky deploy

set fallback := true

# Import network-specific configurations
mod networks
mod modules

# Default recipe shows help information
default:
    @just --list

# Available networks
available-networks:
    @echo "Available networks:"
    @echo "  - holesky (L1: 17000, L2: 393530)"
    @echo "  - sepolia (L1: 11155111, L2: 393531)"
    @echo "  - holesky-l3 (L1: 393530, L2: 934720)"
    @echo "  - sepolia-l3 (L1: 393531, L2: 6296375)"

# Network entry points - these recipes delegate to the appropriate network module
holesky *ARGS:
    @just networks::holesky {{ARGS}}

sepolia *ARGS:
    @just networks::sepolia {{ARGS}}

holesky-l3 *ARGS:
    @just networks::holesky-l3 {{ARGS}}

sepolia-l3 *ARGS:
    @just networks::sepolia-l3 {{ARGS}}

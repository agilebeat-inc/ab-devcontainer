#!/usr/bin/env sh
set -eu

workspace_dir="${1:?workspace directory is required}"
codex_home="${CODEX_HOME:-$HOME/.codex}"

sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock

mkdir -p "$codex_home"

source_file="$workspace_dir/.devcontainer/.codex/config.toml"
destination_file="$codex_home/config.toml"

if [ -f "$source_file" ] && [ ! -e "$destination_file" ]; then
    mkdir -p "$(dirname "$destination_file")"
    cp "$source_file" "$destination_file"
fi

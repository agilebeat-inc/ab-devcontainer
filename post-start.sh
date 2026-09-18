#!/usr/bin/env sh
set -eu

workspace_dir="${1:?workspace directory is required}"

sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock

source_file="$workspace_dir/.devcontainer/.codex/config.toml"
destination_file="$workspace_dir/.codex/config.toml"

if [ -f "$source_file" ] && [ ! -e "$destination_file" ]; then
    mkdir -p "$(dirname "$destination_file")"
    cp "$source_file" "$destination_file"
fi

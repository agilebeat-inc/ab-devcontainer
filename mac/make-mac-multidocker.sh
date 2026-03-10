#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Docker Desktop multi-user setup for macOS
# - Grants Docker CLI access to users (staff or docker-users group)
# - Fixes ~/.docker ownership and permissions
# - Ensures privileged helper is installed
# - Optionally adds users to a custom "docker-users" group
# ============================================

# ---------- Configurable options ----------
# Set to "true" to use a dedicated group (recommended for finer control).
USE_CUSTOM_GROUP="true"
CUSTOM_GROUP_NAME="docker-users"

# Comma-separated list of users to add to CUSTOM_GROUP_NAME.
# Example: TARGET_USERS="alice,bob"
# Leave empty to skip adding users automatically.
TARGET_USERS="${TARGET_USERS:-}"

# If true, attempt to restart Docker Desktop after changes.
RESTART_DOCKER_DESKTOP="true"

# If true, configure all users to use the shared socket at /var/run/docker.sock.
# This lets one desktop session run Docker Desktop while all users use the same daemon.
USE_SHARED_DOCKER_SOCKET="true"
SHARED_DOCKER_SOCKET="/var/run/docker.sock"
SHARED_DOCKER_CONTEXT_NAME="desktop-shared"

# If true, grant all local users read/write access to the shared socket target.
# This applies world traverse permissions on the socket path and mode 666 on socket.
ALLOW_ALL_USERS_SOCKET_RW="true"

# User account that owns/runs Docker Desktop GUI.
# Override at runtime, for example:
#   sudo DOCKER_DESKTOP_OWNER_USER=mdwulit ./make-mac-multidocker.sh
DOCKER_DESKTOP_OWNER_USER="${DOCKER_DESKTOP_OWNER_USER:-$(stat -f '%Su' /dev/console 2>/dev/null || true)}"
# ------------------------------------------

info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

run_with_timeout() {
  local timeout_s="$1"
  shift

  "$@" &
  local pid=$!
  local i=0

  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( i >= timeout_s )); then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
    i=$((i + 1))
  done

  wait "$pid"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Please run as root: sudo $0"
    exit 1
  fi
}

check_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    err "This script is for macOS only."
    exit 1
  fi
}

ensure_docker_app() {
  local app="/Applications/Docker.app"
  if [[ ! -d "$app" ]]; then
    err "Docker Desktop not found at $app. Install it system-wide and re-run."
    exit 1
  fi
  # Make app readable/executable by all users
  info "Ensuring /Applications/Docker.app is readable/executable by users..."
  chmod -R a+rx "$app" || warn "Could not chmod Docker.app; continuing."
}

ensure_privileged_helper() {
  local helper="/Library/PrivilegedHelperTools/com.docker.vmnetd"
  local plist="/Library/LaunchDaemons/com.docker.vmnetd.plist"

  if [[ ! -f "$helper" || ! -f "$plist" ]]; then
    warn "Privileged helper not found. It will be installed when an admin opens Docker Desktop and approves the prompt."
    warn "Open Docker Desktop once as an admin user to finish setting up the helper if networking issues occur."
  else
    info "Privileged helper present: $helper"
  fi
}

ensure_group() {
  local group="$1"

  if dscl . -read /Groups/"$group" >/dev/null 2>&1; then
    info "Group '$group' already exists."
  else
    info "Creating group '$group'..."
    dseditgroup -o create "$group"
    info "Group '$group' created."
  fi

  if [[ -n "$TARGET_USERS" ]]; then
    IFS=',' read -r -a users <<< "$TARGET_USERS"
    for u in "${users[@]}"; do
      u=$(echo "$u" | xargs) # trim
      if id -u "$u" >/dev/null 2>&1; then
        info "Adding user '$u' to group '$group'…"
        dseditgroup -o edit -a "$u" -t user "$group" || warn "Failed to add $u to $group"
      else
        warn "User '$u' does not exist; skipping."
      fi
    done
  fi
}

ensure_all_local_users_in_group() {
  local group="$1"
  while IFS=: read -r user _home; do
    info "Ensuring user '$user' is in group '$group'..."
    dseditgroup -o edit -a "$user" -t user "$group" || warn "Failed to add $user to $group"
  done < <(list_local_users)
}

# Return a list of local, non-system users with valid home directories
list_local_users() {
  dscl . -list /Users | while read -r u; do
    # Skip hidden/service accounts
    [[ "$u" == _* ]] && continue

    # Skip system users
    if id -u "$u" >/dev/null 2>&1; then
      local uid
      uid=$(id -u "$u")
      if (( uid >= 500 )); then
        local home
        local shell
        home=$(dscl . -read /Users/"$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
        shell=$(dscl . -read /Users/"$u" UserShell 2>/dev/null | awk '{print $2}')

        # Only include interactive users with real home directories.
        # Avoid service users that can have homes like /var/empty.
        if [[ -n "$shell" && ( "$shell" == "/usr/bin/false" || "$shell" == "/usr/sbin/nologin" ) ]]; then
          continue
        fi
        if [[ -n "$home" && -d "$home" && "$home" == /Users/* ]]; then
          echo "$u:$home"
        fi
      fi
    fi
  done
}

fix_user_docker_dir() {
  local user="$1"
  local home="$2"
  local group_to_apply="$3"

  local d="$home/.docker"
  local run_dir="$d/run"
  local sock="$run_dir/docker.sock"

  # Create ~/.docker if missing
  if [[ ! -d "$d" ]]; then
    info "Creating $d for $user..."
    mkdir -p "$d"
  fi

  # Ownership: user:group_to_apply (group may be staff or docker-users)
  chown -R "$user:$group_to_apply" "$d" || warn "Failed chown for $d"

  # Permissions: directory 700 by default, files 600
  chmod 700 "$d" || true
  # Apply recursively but be safe about directories vs files
  find "$d" -type d -exec chmod 770 {} \; 2>/dev/null || true
  find "$d" -type f -exec chmod 660 {} \; 2>/dev/null || true

  # Ensure run directory exists and is group-writable
  mkdir -p "$run_dir"
  chown "$user:$group_to_apply" "$run_dir"
  chmod 775 "$run_dir"

  # If a socket exists, make it group-writable
  if [[ -S "$sock" || -e "$sock" ]]; then
    chown "$user:$group_to_apply" "$sock" || true
    chmod 660 "$sock" || true
  fi
}

ensure_user_docker_cli_dir() {
  local user="$1"
  local home="$2"
  local group_to_apply="$3"
  local d="$home/.docker"

  if [[ ! -d "$d" ]]; then
    info "Creating $d for $user..."
    mkdir -p "$d"
  fi

  chown "$user:$group_to_apply" "$d" || warn "Failed chown for $d"
  chmod 700 "$d" || true
}

configure_user_shared_context() {
  local user="$1"
  local context_name="$2"
  local socket_path="$3"
  local user_home
  local user_uid
  local docker_bin
  local cmd
  local output

  user_home=$(dscl . -read /Users/"$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  user_uid=$(id -u "$user" 2>/dev/null || true)
  docker_bin=$(command -v docker || true)

  if [[ -z "$user_home" || -z "$user_uid" ]]; then
    warn "Could not resolve home/uid for user '$user'; skip context setup."
    return
  fi
  if [[ -z "$docker_bin" ]]; then
    warn "Docker CLI not found in PATH; skip context setup for '$user'."
    return
  fi

  # Update if context exists; otherwise create.
  cmd="export HOME='$user_home'; export PATH='/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin'; \
if '$docker_bin' context inspect '$context_name' >/dev/null 2>&1; then \
  '$docker_bin' context update '$context_name' --docker host=unix://$socket_path; \
else \
  '$docker_bin' context create '$context_name' --description 'Shared Docker Desktop socket ($socket_path)' --docker host=unix://$socket_path; \
fi; \
'$docker_bin' context use '$context_name'"

  if ! output=$(launchctl asuser "$user_uid" sudo -H -u "$user" bash -lc "$cmd" 2>&1); then
    warn "Failed configuring context '$context_name' for user '$user': ${output//$'\n'/ | }"
  fi
}

grant_shared_socket_access() {
  local owner_user="$1"
  local group_to_apply="$2"
  local shared_socket="$3"
  local owner_home
  local target_socket
  local run_dir
  local target_docker_dir
  local target_home_dir
  local socket_owner

  owner_home=$(dscl . -read /Users/"$owner_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  if [[ -z "$owner_home" ]]; then
    warn "Could not determine home directory for '$owner_user'; skip socket ACL setup."
    return
  fi
  target_socket="$shared_socket"
  if [[ -L "$shared_socket" ]]; then
    target_socket=$(readlink "$shared_socket")
  fi
  run_dir=$(dirname "$target_socket")
  target_docker_dir=$(dirname "$run_dir")
  target_home_dir=$(dirname "$target_docker_dir")

  # Shared socket may point to a different user's home; always use real target path.
  if [[ "$ALLOW_ALL_USERS_SOCKET_RW" == "true" && "$target_home_dir" == /Users/* && -d "$target_home_dir" ]]; then
    chmod o+x "$target_home_dir" 2>/dev/null || true
    chmod +a "everyone allow search,readattr,readextattr,readsecurity" "$target_home_dir" 2>/dev/null || true
  fi

  if [[ -d "$target_docker_dir" ]]; then
    chgrp "$group_to_apply" "$target_docker_dir" || true
    if [[ "$ALLOW_ALL_USERS_SOCKET_RW" == "true" ]]; then
      chmod 711 "$target_docker_dir" || true
      chmod +a "everyone allow search,readattr,readextattr,readsecurity" "$target_docker_dir" 2>/dev/null || true
    else
      chmod 710 "$target_docker_dir" || true
    fi
    chmod +a "group:$group_to_apply allow search,readattr,readextattr,readsecurity" "$target_docker_dir" 2>/dev/null || true
  fi

  if [[ -d "$run_dir" ]]; then
    chgrp "$group_to_apply" "$run_dir" || true
    if [[ "$ALLOW_ALL_USERS_SOCKET_RW" == "true" ]]; then
      chmod 711 "$run_dir" || true
      chmod +a "everyone allow search,readattr,readextattr,readsecurity" "$run_dir" 2>/dev/null || true
    else
      chmod 775 "$run_dir" || true
    fi
    chmod +a "group:$group_to_apply allow list,add_file,search,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity" "$run_dir" 2>/dev/null || true
    chmod +a#0 "group:$group_to_apply allow read,write,append,readattr,writeattr,readextattr,writeextattr,readsecurity" "$run_dir" 2>/dev/null || true
  fi

  if [[ -S "$target_socket" ]]; then
    socket_owner=$(stat -f '%Su' "$target_socket" 2>/dev/null || true)
    if [[ -n "$socket_owner" && "$socket_owner" != "$owner_user" ]]; then
      warn "Socket owner is '$socket_owner' but DOCKER_DESKTOP_OWNER_USER is '$owner_user'."
      warn "Set DOCKER_DESKTOP_OWNER_USER to '$socket_owner' for consistent restarts."
    fi
    chgrp "$group_to_apply" "$target_socket" || true
    if [[ "$ALLOW_ALL_USERS_SOCKET_RW" == "true" ]]; then
      chmod 666 "$target_socket" || true
    else
      chmod 660 "$target_socket" || true
    fi
  else
    warn "Shared socket not found at '$target_socket' yet; start Docker Desktop and re-run script."
  fi
}

apply_acl_for_future_sockets() {
  # Give the custom group write permission to any future docker.sock created under user homes
  # We add a default ACL entry on the directory so new files inherit group write.
  local group="$1"
  while IFS=: read -r user home; do
    local run_dir="$home/.docker/run"
    if [[ -d "$run_dir" ]]; then
      info "Applying inheritable ACL for group '$group' on $run_dir..."
      # Grant group read/write/execute and make it inheritable (default)
      chmod +a "group:$group allow list,add_file,search,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity" "$run_dir" 2>/dev/null || true
      chmod +a#0 "group:$group allow read,write,append,readattr,writeattr,readextattr,writeextattr,readsecurity" "$run_dir" 2>/dev/null || true
    fi
  done < <(list_local_users)
}

restart_docker_desktop() {
  local owner_user="$1"

  if [[ "$RESTART_DOCKER_DESKTOP" != "true" ]]; then
    return
  fi

  local app="/Applications/Docker.app"
  if [[ ! -d "$app" ]]; then
    warn "Docker.app not found at $app; skip restart."
    return
  fi

  if [[ -z "$owner_user" ]] || ! id -u "$owner_user" >/dev/null 2>&1; then
    warn "DOCKER_DESKTOP_OWNER_USER is not set to a valid user; skip restart."
    return
  fi

  local owner_uid
  owner_uid=$(id -u "$owner_user")
  local console_user
  console_user=$(stat -f '%Su' /dev/console 2>/dev/null || true)

  if [[ -n "$console_user" && "$console_user" != "$owner_user" ]]; then
    warn "Owner user '$owner_user' is not active console user ('$console_user'); skip auto-restart to avoid GUI hang."
    warn "Log in as '$owner_user' and launch /Applications/Docker.app manually."
    return
  fi

  info "Attempting to restart Docker Desktop..."
  # Quit only when app is actually running; avoid AppleScript -600 noise.
  if pgrep -u "$owner_uid" -x Docker >/dev/null 2>&1 || pgrep -u "$owner_uid" -f "Docker.app/Contents/MacOS/Docker" >/dev/null 2>&1; then
    if ! run_with_timeout 10 launchctl asuser "$owner_uid" /usr/bin/osascript -e 'tell application "Docker" to quit' >/dev/null 2>&1; then
      warn "AppleScript quit failed; sending TERM to Docker process."
      pkill -u "$owner_uid" -x Docker >/dev/null 2>&1 || true
      pkill -u "$owner_uid" -f "Docker.app/Contents/MacOS/Docker" >/dev/null 2>&1 || true
    fi

    # Wait up to 20s for shutdown.
    for i in {1..20}; do
      pgrep -u "$owner_uid" -x Docker >/dev/null 2>&1 || pgrep -u "$owner_uid" -f "Docker.app/Contents/MacOS/Docker" >/dev/null 2>&1 || break
      sleep 1
    done

    if pgrep -u "$owner_uid" -x Docker >/dev/null 2>&1 || pgrep -u "$owner_uid" -f "Docker.app/Contents/MacOS/Docker" >/dev/null 2>&1; then
      warn "Docker is still running; forcing stop."
      pkill -9 -u "$owner_uid" -x Docker >/dev/null 2>&1 || true
      pkill -9 -u "$owner_uid" -f "Docker.app/Contents/MacOS/Docker" >/dev/null 2>&1 || true
      sleep 1
    fi
  else
    info "Docker Desktop is not running; starting it."
  fi

  # Start
  run_with_timeout 10 launchctl asuser "$owner_uid" /usr/bin/open -ga "$app" \
    || warn "Could not launch Docker Desktop for '$owner_user'. You may need to start it manually."
}

main() {
  require_root
  check_macos

  info "Starting Docker Desktop multi-user setup..."

  ensure_docker_app
  ensure_privileged_helper

  local group_to_use="staff"
  if [[ "$USE_CUSTOM_GROUP" == "true" ]]; then
    group_to_use="$CUSTOM_GROUP_NAME"
    ensure_group "$group_to_use"
    if [[ "$USE_SHARED_DOCKER_SOCKET" == "true" && -z "${TARGET_USERS// }" ]]; then
      info "Shared mode enabled and TARGET_USERS is empty; adding all local users to '$group_to_use'."
      ensure_all_local_users_in_group "$group_to_use"
    fi
  else
    info "Using default macOS 'staff' group for permissions."
  fi

  if [[ "$USE_SHARED_DOCKER_SOCKET" == "true" ]]; then
    info "Configuring shared socket mode using $SHARED_DOCKER_SOCKET..."
  else
    info "Fixing ~/.docker ownership and permissions for users..."
  fi
  while IFS=: read -r user home; do
    if [[ "$USE_SHARED_DOCKER_SOCKET" == "true" ]]; then
      info "Configuring shared Docker context for user '$user' ($home)..."
      ensure_user_docker_cli_dir "$user" "$home" "$group_to_use"
      configure_user_shared_context "$user" "$SHARED_DOCKER_CONTEXT_NAME" "$SHARED_DOCKER_SOCKET"
    else
      info "Configuring per-user socket permissions for user '$user' ($home)..."
      fix_user_docker_dir "$user" "$home" "$group_to_use"
    fi
  done < <(list_local_users)

  if [[ "$USE_SHARED_DOCKER_SOCKET" != "true" && "$USE_CUSTOM_GROUP" == "true" ]]; then
    apply_acl_for_future_sockets "$group_to_use"
  fi

  restart_docker_desktop "$DOCKER_DESKTOP_OWNER_USER"

  if [[ "$USE_SHARED_DOCKER_SOCKET" == "true" ]]; then
    grant_shared_socket_access "$DOCKER_DESKTOP_OWNER_USER" "$group_to_use" "$SHARED_DOCKER_SOCKET"
  fi

  cat <<EOF

=========================================================
✅ Finished.

Next steps for users:
  1) Log out and back in (or run: 'exec su - \$USER') if you were added to a new group.
  2) Ensure Docker Desktop is running as: ${DOCKER_DESKTOP_OWNER_USER:-<unset>}.
  3) Run:
       docker version
       docker run --rm hello-world

Notes:
  • Shared mode: ${USE_SHARED_DOCKER_SOCKET}
  • Shared socket path: ${SHARED_DOCKER_SOCKET}
  • Shared context name: ${SHARED_DOCKER_CONTEXT_NAME}
  • All-users socket RW: ${ALLOW_ALL_USERS_SOCKET_RW}
  • In Docker Desktop, enable "Allow the default Docker socket to be used"
    so ${SHARED_DOCKER_SOCKET} is available for all users.
  • If any user ever runs 'sudo docker', their ~/.docker may become root-owned.
    Fix with:
      sudo chown -R \$USER:${group_to_use} ~/.docker
      find ~/.docker -type d -exec chmod 770 {} \\;
      find ~/.docker -type f -exec chmod 660 {} \\;
  • If networking fails, open Docker Desktop once as an admin to approve the
    privileged helper (com.docker.vmnetd).
  • Re-run this script safely anytime.

Group in use: ${group_to_use}
Added users:  ${TARGET_USERS:-<none>}
=========================================================
EOF
}

main "$@"

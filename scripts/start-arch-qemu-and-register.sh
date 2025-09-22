#!/usr/bin/env bash
set -euo pipefail

# Configuration (override via env vars)
IMAGE_PATH=${IMAGE_PATH:-"/Users/vishal/Projects/Guacamole/images/Arch-Linux-x86_64-basic.qcow2"}
QEMU_BIN=${QEMU_BIN:-"qemu-system-x86_64"}
MEMORY_MB=${MEMORY_MB:-"2048"}
CPUS=${CPUS:-"2"}
ACCEL=${ACCEL:-"hvf"} # macOS Intel: hvf, Linux: kvm (if available)
HOST_ARCH=$(uname -m)

# If running on Apple Silicon and attempting x86_64, HVF is not available for x86 guests.
# Fall back to TCG and use a generic QEMU CPU model for compatibility.
if [[ "$HOST_ARCH" == "arm64" || "$HOST_ARCH" == "aarch64" ]]; then
  if [[ "${QEMU_BIN}" == *"qemu-system-x86_64"* ]]; then
    ACCEL="tcg"
    CPU_MODEL_DEFAULT="qemu64"
  else
    CPU_MODEL_DEFAULT="host"
  fi
else
  CPU_MODEL_DEFAULT="host"
fi

CPU_MODEL=${CPU_MODEL:-"${CPU_MODEL_DEFAULT}"}

# VNC configuration
VNC_BIND_ADDR=${VNC_BIND_ADDR:-"127.0.0.1"}
VNC_DISPLAY_NUM=${VNC_DISPLAY_NUM:-"1"} # :1 → 5901
VNC_PORT=$((5900 + VNC_DISPLAY_NUM))

# Host forwards (optional)
HOSTFWD_SSH_PORT=${HOSTFWD_SSH_PORT:-"2222"}

# Guacamole configuration
GUAC_URL=${GUAC_URL:-"http://localhost:8888"}  # base URL; script will detect context path
GUAC_USER=${GUAC_USER:-"guacadmin"}
GUAC_PASS=${GUAC_PASS:-"guacadmin"}
GUAC_CONNECTION_NAME=${GUAC_CONNECTION_NAME:-"Arch Linux (QEMU VNC)"}

# Runtime files
RUNTIME_DIR=${RUNTIME_DIR:-"/Users/vishal/Projects/Guacamole/.runtime"}
mkdir -p "$RUNTIME_DIR"
PIDFILE="$RUNTIME_DIR/qemu-arch.pid"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  if ! command_exists "$1"; then
    echo "Error: required command '$1' not found in PATH" >&2
    exit 1
  fi
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "Error: file not found: $1" >&2
    exit 1
  fi
}

wait_for_port() {
  local host="$1" port="$2" timeout="${3:-30}"
  local start ts
  start=$(date +%s)
  while true; do
    if nc -z "$host" "$port" 2>/dev/null; then
      return 0
    fi
    ts=$(date +%s)
    if [ $((ts - start)) -ge "$timeout" ]; then
      return 1
    fi
    sleep 1
  done
}

require_cmd "$QEMU_BIN"
require_cmd "curl"
require_cmd "nc"
require_cmd "jq"
require_file "$IMAGE_PATH"

echo "Starting QEMU for image: $IMAGE_PATH"

# If an old instance is running, stop it first
if [ -f "$PIDFILE" ]; then
  if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Found existing QEMU (PID $(cat "$PIDFILE")), terminating..."
    kill "$(cat "$PIDFILE")" || true
    sleep 2
  fi
  rm -f "$PIDFILE"
fi

# Networking (user mode with SSH forward)
NETDEV_ARGS=("-netdev" "user,id=net0,hostfwd=tcp:127.0.0.1:${HOSTFWD_SSH_PORT}-:22")
NETDEV_ARGS+=("-device" "e1000,netdev=net0")

# Display (headless with VNC)
DISPLAY_ARGS=("-display" "none" "-vnc" "${VNC_BIND_ADDR}:${VNC_DISPLAY_NUM}")

# Acceleration (best effort)
ACCEL_ARGS=("-accel" "$ACCEL")

echo "Launching QEMU in daemon mode with VNC at ${VNC_BIND_ADDR}:${VNC_DISPLAY_NUM} (port ${VNC_PORT})"
"$QEMU_BIN" \
  -daemonize \
  -pidfile "$PIDFILE" \
  -name "arch-linux-qemu" \
  -machine q35,graphics=off \
  -cpu "$CPU_MODEL" \
  -smp "$CPUS" \
  -m "$MEMORY_MB" \
  "${ACCEL_ARGS[@]}" \
  -drive "file=${IMAGE_PATH},if=virtio,cache=writeback,discard=unmap,format=qcow2" \
  "${NETDEV_ARGS[@]}" \
  "${DISPLAY_ARGS[@]}"

echo "Waiting for VNC to be available on ${VNC_BIND_ADDR}:${VNC_PORT}..."
if ! wait_for_port "$VNC_BIND_ADDR" "$VNC_PORT" 60; then
  echo "Warning: VNC port ${VNC_PORT} not reachable yet. Continuing to register in Guacamole."
fi

# Authenticate to Guacamole
trim_trailing_slash() { echo "$1" | sed 's:/*$::'; }
BASE_URL=$(trim_trailing_slash "$GUAC_URL")
CANDIDATES=(
  "${BASE_URL}/api"
  "${BASE_URL}/guacamole/api"
)

GUAC_API_BASE=""
AUTH_JSON=""
HTTP_CODE=""
for candidate in "${CANDIDATES[@]}"; do
  RESP=$(curl -sS -w "\n%{http_code}" -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "username=${GUAC_USER}" \
    --data-urlencode "password=${GUAC_PASS}" \
    "${candidate}/tokens") || true
  BODY="$(printf "%s" "$RESP" | sed '$d')"
  CODE="$(printf "%s" "$RESP" | tail -n1)"
  echo "Tried ${candidate}/tokens -> HTTP ${CODE}" >&2
  if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.authToken? // empty' >/dev/null; then
    GUAC_API_BASE="$candidate"
    AUTH_JSON="$BODY"
    HTTP_CODE="$CODE"
    break
  fi
  HTTP_CODE="$CODE"
  AUTH_JSON="$BODY"
done

echo "Auth HTTP: ${HTTP_CODE}" >&2
echo "Auth body: ${AUTH_JSON}" >&2

if [ -z "$GUAC_API_BASE" ]; then
  echo "Error: could not determine Guacamole API base from $GUAC_URL (tried /api and /guacamole/api)." >&2
  exit 1
fi

AUTH_TOKEN=$(echo "$AUTH_JSON" | jq -r '.authToken')
DATA_SOURCE=$(echo "$AUTH_JSON" | jq -r '.dataSource')
AUTH_QS="token=${AUTH_TOKEN}"

echo "Authenticated. api=${GUAC_API_BASE} dataSource=${DATA_SOURCE}" >&2

# List existing connections
CONNECTIONS_JSON=$(curl -sS -H 'Accept: application/json' \
  "${GUAC_API_BASE}/session/data/${DATA_SOURCE}/connections?${AUTH_QS}")
echo "Existing connections: $(echo "$CONNECTIONS_JSON" | jq -r 'map(.name) | join(", ")')" >&2

EXISTING_ID=$(echo "$CONNECTIONS_JSON" | jq -r --arg name "$GUAC_CONNECTION_NAME" '.[] | select(.name==$name) | .identifier' | head -n1 || true)

BODY_JSON=$(cat <<EOF
{
  "parentIdentifier": "ROOT",
  "name": "${GUAC_CONNECTION_NAME}",
  "protocol": "vnc",
  "attributes": {
    "max-connections": "",
    "max-connections-per-user": "",
    "weight": "",
    "failover-only": "",
    "guacd-encryption": "",
    "guacd-hostname": "",
    "guacd-port": ""
  },
  "parameters": {
    "hostname": "host.docker.internal",
    "port": "${VNC_PORT}",
    "password": ""
  }
}
EOF
)

if [ -n "${EXISTING_ID:-}" ]; then
  echo "Updating existing Guacamole connection '${GUAC_CONNECTION_NAME}' (id=${EXISTING_ID})..." >&2
  RESP=$(curl -sS -w "\n%{http_code}" -X PUT \
    -H 'Content-Type: application/json' \
    -d "$BODY_JSON" \
    "${GUAC_API_BASE}/session/data/${DATA_SOURCE}/connections/${EXISTING_ID}?${AUTH_QS}")
  BODY="$(printf "%s" "$RESP" | sed '$d')"; CODE="$(printf "%s" "$RESP" | tail -n1)"
  echo "Update HTTP ${CODE} body: ${BODY}" >&2
  CONNECTION_ID="$EXISTING_ID"
else
  echo "Creating new Guacamole connection '${GUAC_CONNECTION_NAME}'..." >&2
  RESP=$(curl -sS -w "\n%{http_code}" -X POST \
    -H 'Content-Type: application/json' \
    -d "$BODY_JSON" \
    "${GUAC_API_BASE}/session/data/${DATA_SOURCE}/connections?${AUTH_QS}")
  BODY="$(printf "%s" "$RESP" | sed '$d')"; CODE="$(printf "%s" "$RESP" | tail -n1)"
  echo "Create HTTP ${CODE} body: ${BODY}" >&2
  CONNECTION_ID=$(echo "$BODY" | jq -r '.identifier // empty')
fi

# If identifier not captured, try to re-fetch it
if [ -z "${CONNECTION_ID:-}" ]; then
  CONNECTIONS_JSON=$(curl -sS -H 'Accept: application/json' \
    "${GUAC_API_BASE}/session/data/${DATA_SOURCE}/connections?${AUTH_QS}")
  CONNECTION_ID=$(echo "$CONNECTIONS_JSON" | jq -r --arg name "$GUAC_CONNECTION_NAME" '.[] | select(.name==$name) | .identifier' | head -n1 || true)
fi

if [ -z "${CONNECTION_ID:-}" ]; then
  echo "Error: could not determine connection ID for '${GUAC_CONNECTION_NAME}'." >&2
  exit 1
fi

# Ensure guacadmin has permissions to see it
PERMS_PAYLOAD=$(cat <<EOF
[
  {"op":"add", "path":"/connectionPermissions/${CONNECTION_ID}", "value":"READ"},
  {"op":"add", "path":"/connectionPermissions/${CONNECTION_ID}", "value":"UPDATE"},
  {"op":"add", "path":"/connectionPermissions/${CONNECTION_ID}", "value":"ADMINISTER"}
]
EOF
)

PERM_RESP=$(curl -sS -w "\n%{http_code}" -X PATCH \
  -H 'Content-Type: application/json' \
  -d "$PERMS_PAYLOAD" \
  "${GUAC_API_BASE}/session/data/${DATA_SOURCE}/users/${GUAC_USER}/permissions?${AUTH_QS}")
PERM_BODY="$(printf "%s" "$PERM_RESP" | sed '$d')"; PERM_CODE="$(printf "%s" "$PERM_RESP" | tail -n1)"
echo "Permissions HTTP ${PERM_CODE} body: ${PERM_BODY}" >&2

# Final listing
FINAL_LIST=$(curl -sS -H 'Accept: application/json' \
  "${GUAC_API_BASE}/session/data/${DATA_SOURCE}/connections?${AUTH_QS}")
echo "Final connections: $(echo "$FINAL_LIST" | jq -r 'map(.name) | join(", ")')" >&2

echo "Done. QEMU is running (PID: $(cat "$PIDFILE" 2>/dev/null || echo unknown)), VNC at ${VNC_BIND_ADDR}:${VNC_PORT}."
echo "Open Guacamole at: ${GUAC_URL} and use connection '${GUAC_CONNECTION_NAME}'"
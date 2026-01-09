#!/bin/bash
set -euo pipefail
SCRIPT_VERSION="v2.2.0"

echo " ============================================================ "
echo " BAZZITE-UNRAID TMUX LAUNCHER $SCRIPT_VERSION"
echo " ************************************************************ "

# ------------------------------------------------------------
# Load environment
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/bazzite-unraid.env"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: Missing env file: $ENV_FILE"; exit 1; }
source "$ENV_FILE"
export DISPLAY
export XAUTHORITY

distrobox stop $CONTAINER_NAME -Y

# ------------------------------------------------------------
# Identity
# ------------------------------------------------------------
id "$HOST_USER" >/dev/null 2>&1 || {
    echo "ERROR: Host user '$HOST_USER' does not exist"
    exit 1
}

CONTAINER_UID=$(id -u "$HOST_USER")
CONTAINER_GID=$(id -g "$HOST_USER")

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
DISTROBOX_BIN="$(command -v distrobox)"
CONT_HOME="/home/${HOST_USER}"

LOG_DIR="${LOG_BASE}/${CONTAINER_NAME}"
HOST_LOGS_MOUNT="/host-logs"

TMUX_SESSION="$CONTAINER_NAME"

XFCE_READY_FILE="$CONT_HOME/.xfce-ready"
XFCE_PID_FILE="$CONT_HOME/.xfce-pid"

# ------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------
[[ $EUID -eq 0 ]] || { echo "ERROR: Must run as root on Unraid"; exit 1; }

for cmd in tmux "$DISTROBOX_BIN" xrandr; do
    command -v "$cmd" >/dev/null || { echo "Missing command: $cmd"; exit 1; }
done

pgrep -x Xorg >/dev/null || { echo "ERROR: Xorg not running"; exit 1; }

# ------------------------------------------------------------
# Pre-flight check: verify container home is writable
# ------------------------------------------------------------
if ! sudo -u "$HOST_USER" test -w "$CONTAINER_HOME" 2>/dev/null; then
    echo "ERROR: Container home is not writable by $HOST_USER ($CONTAINER_UID:$CONTAINER_GID)"
    echo "  Home directory: $CONTAINER_HOME"
    echo "  On Unraid, make sure the host directory is owned by UID $CONTAINER_UID and GID $CONTAINER_GID"
    echo "  Example:"
    echo "    chown -R $CONTAINER_UID:$CONTAINER_GID \"$CONTAINER_HOME\""
    echo "    chmod -R 700 \"$CONTAINER_HOME/.config\""
    exit 1
fi

if ! sudo -u "$HOST_USER" test -r "$CONTAINER_HOME/.config/bazzite-unraid.env" 2>/dev/null; then
    echo "ERROR: Cannot read .config/bazzite-unraid.env as $HOST_USER"
    echo "  Check file exists and is readable (chmod 600-700 as needed)"
    exit 1
fi

echo "✓ Container home and .config are accessible by $HOST_USER"

# ------------------------------------------------------------
# X11 access
# ------------------------------------------------------------
if command -v xhost >/dev/null 2>&1; then
    xhost +SI:localuser:"$HOST_USER" >/dev/null
    xhost +SI:localuser:root >/dev/null
    xhost +local: >/dev/null
fi

# ------------------------------------------------------------
# Resolution detection
# ------------------------------------------------------------
read -r MONITOR_RES <<< "$(xrandr | awk '/\*/ {print $1; exit}')"
RES_W=${MONITOR_RES%x*}
RES_H=${MONITOR_RES#*x}
echo "✓ Detected resolution: $RES_W x $RES_H"

# ------------------------------------------------------------
# Kill stale sessions
# ------------------------------------------------------------
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
sudo -u "$HOST_USER" "$DISTROBOX_BIN" enter "$CONTAINER_NAME" \
    -- tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

echo "✓ Old tmux sessions cleared"

# ============================================================
# Create tmux session inside container
# ============================================================
sudo -u "$HOST_USER" "$DISTROBOX_BIN" enter "$CONTAINER_NAME" -- bash -c "
tmux new-session -d -s '$TMUX_SESSION' -n main
tmux set-option -g mouse on
tmux set-option -g history-limit 200000
cd '$CONT_HOME'
source '$CONT_HOME/.config/bazzite-unraid.env' || true
"

container_tmux() {
    sudo -u "$HOST_USER" "$DISTROBOX_BIN" enter "$CONTAINER_NAME" -- tmux "$@"
}

echo "✓ TMUX session '$TMUX_SESSION' ready"

# ============================================================
# Layout
# ============================================================
container_tmux split-window -v -t 0
container_tmux resize-pane -t 0 -y 20%
container_tmux resize-pane -t 1 -y 80%

# ============================================================
# Pane 1 — Logs
# ============================================================
container_tmux send-keys -t 0 "
printf '\033]2;1b-Logs\033\\'
tail -f '$HOST_LOGS_MOUNT'/*.log
" C-m

# ============================================================
# Pane 2 — XFCE + Sunshine
# ============================================================
container_tmux send-keys -t 1 "
printf '\033]2;2-XFCE+Sunshine\033\\'
cd '$CONT_HOME'
source '$CONT_HOME/.config/bazzite-unraid.env' || true

rm -f '$XFCE_READY_FILE' '$XFCE_PID_FILE'

while true; do
    echo '[XFCE+Sunshine] starting XFCE session'

    # Start D-Bus session bus if not running
    if [ -z \"\$DBUS_SESSION_BUS_ADDRESS\" ]; then
        eval \$(dbus-launch --sh-syntax)
    fi

    # Start XFCE in background with nohup
    nohup startxfce4 > '$HOST_LOGS_MOUNT/xfce.log' 2>&1 &
    XFCE_PID=\$!
    disown

    sleep 10

    if pgrep -x xfce4-session >/dev/null; then
        echo '[XFCE+Sunshine] XFCE running successfully'
    else
        echo '[XFCE+Sunshine] ERROR: XFCE not detected'
        cat '$HOST_LOGS_MOUNT/xfce.log' | tail -20
        sleep 5
        continue
    fi

    touch '$XFCE_READY_FILE'
    echo \$XFCE_PID > '$XFCE_PID_FILE'

    echo '[XFCE+Sunshine] Starting Sunshine'
    sunshine 2>&1 | tee -a '$HOST_LOGS_MOUNT/sunshine.log'

    echo '[XFCE+Sunshine] Sunshine exited, restarting'
    pkill -9 xfce4-session xfdesktop xfce4-panel || true
    rm -f '$XFCE_READY_FILE' '$XFCE_PID_FILE'
    sleep 5
done
" C-m

sleep 5

# ============================================================
# Pane 3 — Steam Big Picture
# ============================================================
# container_tmux send-keys -t 2 "
# printf '\033]2;2c-Steam\033\\'
# cd '$CONT_HOME'
# source '$CONT_HOME/.config/bazzite-unraid.env' || true

# while ! pgrep -x xfce4-session >/dev/null; do sleep 1; done

# while true; do
#   steam -bigpicture -tenfoot \
#     >> '$HOST_LOGS_MOUNT/steam.log' 2>&1
#   sleep 5
# done
# " C-m

# ============================================================
# Attach
# ============================================================
exec sudo -u "$HOST_USER" "$DISTROBOX_BIN" enter "$CONTAINER_NAME" \
    -- tmux attach-session -t "$TMUX_SESSION"

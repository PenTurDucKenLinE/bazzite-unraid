#!/bin/bash
set -euo pipefail

# ============================================================
# BAZZITE-UNRAID GOLDEN DISTROBOX SCRIPT
# Purpose: Create and run a bazzite-unraid container on Unraid
# Features:
#   - Headless-safe (fallback XDG_RUNTIME_DIR)
#   - Auto-user switch to $HOST_USER
#   - GPU / audio / input / USB device mapping
#   - Host group alignment
#   - Sunshine and XFCE runtime setup
#   - Hardware validation (Vulkan, Sunshine, GameMode)
#   - Interactive root/$HOST_USER password setup
# ============================================================
# TODO:
#   - Redirect home to /mnt/user/system/home/rock
# ============================================================

# ------------------------------------------------------------
# Load environment variables
# ------------------------------------------------------------
# shellcheck source=/dev/null
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/bazzite-unraid.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Environment file not found: $ENV_FILE"
    exit 1
fi

source "$ENV_FILE"

# ------------------------------------------------------------
# Set container paths and arguments
# ------------------------------------------------------------
# Set container paths
CONTAINER_CONFIG=$CONTAINER_HOME/.config
LOG_DIR="${LOG_BASE}/${CONTAINER_NAME}"
LOG_FILE="$LOG_DIR/distrobox_create.log"

# Build distrobox group-add arguments as an array
DISTRO_GROUPS=()
for grp in "${HOST_GROUP_NAMES[@]}"; do
    DISTRO_GROUPS+=("--group-add" "$grp")
done
DISTRO_GROUPS_STR="${DISTRO_GROUPS[*]}"

# Resolve host group GIDs and build parallel array
echo "Resolving host group GIDs..."
HOST_GROUP_GIDS=()  # Initialize array
for grp in "${HOST_GROUP_NAMES[@]}"; do
    if ! getent group "$grp" >/dev/null 2>&1; then
        echo "WARNING: Host group '$grp' does not exist; skipping"
        continue
    fi
    gid="$(getent group "$grp" | cut -d: -f3)"
    HOST_GROUP_GIDS+=("$gid")  # Append directly to array
    echo " $grp → $gid"
done
HOST_GROUP_NAMES_STR="${HOST_GROUP_NAMES[*]}"
HOST_GROUP_GIDS_STR="${HOST_GROUP_GIDS[*]}"

# ------------------------------------------------------------
# Pre-flight directories & log
# ------------------------------------------------------------
mkdir -p "$CONTAINER_HOME" "$CONTAINER_CONFIG" "$LOG_DIR" "$XDG_RUNTIME_DIR"
#su -s /bin/bash -c "chmod 755 $CONTAINER_HOME $CONTAINER_CONFIG $LOG_DIR && chmod 700 $XDG_RUNTIME_DIR" root
#su -s /bin/bash -c "chmod 700 $XDG_RUNTIME_DIR" root
cp -f "$ENV_FILE" "$CONTAINER_CONFIG/"

echo "Log file: $LOG_FILE"
rm -f $LOG_FILE

# Use the following to redirect all output to a logfile: {} 2>&1 | tee -a "$LOG_FILE"
{
date
# ------------------------------------------------------------
# User and Distrobox checks
# ------------------------------------------------------------
CURRENT_UID=$(id -u)
if [[ "$CURRENT_UID" -eq 0 ]]; then
    echo "ERROR: This script must be run as the non-root user $HOST_USER (UID: $(id -u $HOST_USER))."
    echo "Please switch to $HOST_USER and run the script again."
    exit 1
fi
if [[ "$(getent passwd "$HOST_USER" | cut -d: -f7)" == "/bin/false" ]]; then
    echo "ERROR: $HOST_USER has /bin/false as shell. This user cannot run Distrobox."
    exit 1
fi
if [[ "$(getent passwd "$HOST_USER" | cut -d: -f6)" == "/" ]]; then
    echo "ERROR: $HOST_USER has / as home directory. This is invalid for Distrobox."
    exit 1
fi


# ------------------------------------------------------------
# UID/GID
# ------------------------------------------------------------
HOST_UID=$(id -u "$HOST_USER")
HOST_GID=$(id -g "$HOST_USER")

echo "============================================================"
echo " BAZZITE-UNRAID GOLDEN SCRIPT"
echo "============================================================"
echo "  Container                     : $CONTAINER_NAME"
echo "  Image                         : $IMAGE_NAME"
echo "  Host user                     : $HOST_USER ($HOST_UID:$HOST_GID)"
echo "  Container home                : $CONTAINER_HOME"
echo "  Log directory                 : $LOG_DIR"
show_env
echo "============================================================"

# ------------------------------------------------------------
# Check ownership of container home and log directories
# ------------------------------------------------------------
for dir in "$CONTAINER_HOME" "$LOG_DIR"; do
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Directory '$dir' does not exist. Please create it first."
        exit 1
    fi

    # Get current owner UID and GID
    current_uid=$(stat -c "%u" "$dir")
    current_gid=$(stat -c "%g" "$dir")

    if [[ "$current_uid" -ne "$HOST_UID" || "$current_gid" -ne "$HOST_GID" ]]; then
        echo "ERROR: '$dir' is not owned by $HOST_UID:$HOST_GID (current: $current_uid:$current_gid)"
        echo "On Unraid, /mnt/user shares cannot be chowned from a container."
        echo "Please fix ownership on the host before running this script:"
        echo "  chown -R $HOST_UID:$HOST_GID \"$dir\""
        exit 1
    else
        echo "✓ Ownership of '$dir' is correct ($HOST_UID:$HOST_GID)"
    fi
done


# ------------------------------------------------------------
# Cleanup any previous container
# ------------------------------------------------------------
distrobox stop "$CONTAINER_NAME" -Y 2>/dev/null || true
distrobox rm   "$CONTAINER_NAME" -Y 2>/dev/null || true

# ============================================================
# CREATE DISTROBOX CONTAINER
# ============================================================
distrobox-create \
  --name "$CONTAINER_NAME" \
  --image "$IMAGE_NAME" \
  --init \
  -a "--env DISPLAY=$DISPLAY" \
  -a "--env XAUTHORITY=$XAUTHORITY" \
  -a "--env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
  -a "--env HOST_GROUP_NAMES_STR=\"$HOST_GROUP_NAMES_STR\"" \
  -a "--env HOST_GROUP_GIDS_STR=\"$HOST_GROUP_GIDS_STR\"" \
  -a "--volume $LOG_DIR:/host-logs:rw" \
  -a "--volume $CONTAINER_HOME:/home/$HOST_USER:rw" \
  -a "--volume $CONTAINER_CONFIG:/home/$HOST_USER/.config:rw" \
  -a "--volume /tmp/.X11-unix:/tmp/.X11-unix:rw" \
  -a "--volume $XAUTHORITY:$XAUTHORITY:ro" \
  -a "--volume $XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR" \
  -a "--device /dev/dri/card0:rmw" \
  -a "--device /dev/dri/renderD128:rmw" \
  -a "--device /dev/kfd:rmw" \
  -a "--device /dev/snd:rmw" \
  -a "--device /dev/input:rmw" \
  -a "--device /dev/uinput:rmw" \
  -a "--device /dev/bus/usb:rmw" \
  -a "$DISTRO_GROUPS_STR" \
  -a "--cap-add SYS_ADMIN" \
  -a "--cap-add SYS_PTRACE" \
  -a "--security-opt seccomp=unconfined" \
  -a "--ipc host"
  

echo ""
echo "✔ Container '$CONTAINER_NAME' created successfully"
echo ""

# ============================================================
# NON-ROOT USER SETUP & ID ALIGNMENT
# ============================================================
distrobox-enter "$CONTAINER_NAME" -- bash <<'EOF_IDS'
set -e

HOST_USER=$(id -un)

echo " "
echo "Runtime setup as: $HOST_USER ($(id -u):$(id -g))"
echo "Host Group Names: $HOST_GROUP_NAMES_STR"
echo "Host Group GIDs:  $HOST_GROUP_GIDS_STR"
echo " "

# ------------------------------------------------------------
# Backup sudoers and enable passwordless sudo for HOST_USER
# ------------------------------------------------------------
sudo cp /etc/sudoers /etc/sudoers.bak
sudo sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sudo chmod 0440 /etc/sudoers
sudo find /etc/sudoers.d -type f -exec chmod 0440 {} \; || true
sudo visudo -c || true

echo "$HOST_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-$HOST_USER-nopasswd
sudo chmod 0440 /etc/sudoers.d/90-$HOST_USER-nopasswd

# ------------------------------------------------------------
# Align container groups with host GIDs
# ------------------------------------------------------------
# Define arrays explicitly from strings
HOST_GROUP_NAMES=($HOST_GROUP_NAMES_STR)
HOST_GROUP_GIDS=($HOST_GROUP_GIDS_STR)

# Loop over arrays safely under set -u
for i in "${!HOST_GROUP_NAMES[@]}"; do
    grp="${HOST_GROUP_NAMES[$i]}"
    gid="${HOST_GROUP_GIDS[$i]}"
    echo "✓ Aligning container group '$grp' to host GID $gid"

    if [[ -z "$gid" ]]; then
        echo "ERROR: GID for $grp not provided"
        exit 1
    fi

    if ! getent group "$grp" >/dev/null; then
        sudo groupadd "$grp"
    fi
    sudo groupmod -o -g "$gid" "$grp"
    sudo usermod -aG "$grp" "$HOST_USER"
done
EOF_IDS

# ============================================================
# RUNTIME SETUP INSIDE CONTAINER
# ============================================================
distrobox-enter "$CONTAINER_NAME" -- bash <<'EOF_RUNTIME'
# ------------------------------------------------------------
# Ensure /dev/uinput permissions for Sunshine
# ------------------------------------------------------------
if [[ -e /dev/uinput ]]; then
    sudo chgrp input /dev/uinput
    sudo chmod 660 /dev/uinput
    echo "✓ /dev/uinput permissions set"
fi

# ------------------------------------------------------------
# Create .xinitrc for XFCE if missing
# ------------------------------------------------------------
if [[ ! -f "$HOME/.xinitrc" ]]; then
    echo "exec startxfce4" > "$HOME/.xinitrc"
    sudo chmod 644 "$HOME/.xinitrc"
    echo "✓ .xinitrc created"
else
    echo "✓ .xinitrc already exists"
fi

# ------------------------------------------------------------
# Sunshine installation
# ------------------------------------------------------------
if ! command -v sunshine >/dev/null 2>&1; then
    echo "Installing Sunshine..."
    echo -e "[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download" >> /etc/pacman.conf
    pacman -Sy --noconfirm
    pacman -S --noconfirm lizardbyte/sunshine
fi

SUNSHINE_BIN=$(command -v sunshine)
if [[ -n "$SUNSHINE_BIN" ]]; then
    echo "✓ Sunshine binary found at $SUNSHINE_BIN"
    setcap cap_sys_admin,cap_net_admin+ep "$SUNSHINE_BIN" 2>/dev/null || true
fi

if [ -f /var/run/slim.auth ]; then
  ln -sf /var/run/slim.auth "$HOME/.Xauthority"
fi

# ------------------------------------------------------------
# Hardware & environment validation
# ------------------------------------------------------------
echo ""
echo "---- USER / GROUPS ----"
id

echo ""
echo "---- GPU DEVICES ----"
ls -l /dev/dri || true
ls -l /dev/kfd || true

echo ""
echo "---- VULKAN CHECK ----"
if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary | sed -n '1,30p'
else
    echo "WARNING: vulkaninfo not found"
fi

echo ""
echo "---- OPENGL CHECK ----"
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo -B
else
    echo "glxinfo not installed (non-fatal)"
fi

echo ""
echo "---- SUNSHINE CHECK ----"
if command -v sunshine >/dev/null 2>&1; then
    sunshine --version || true
else
    echo "WARNING: sunshine not found"
fi

echo ""
echo "---- GAMEMODE CHECK ----"
if command -v gamemoded >/dev/null 2>&1; then
    gamemoded -t || true
else
    echo "WARNING: gamemoded not found"
fi

echo ""
echo "============================================================"
echo " VALIDATION COMPLETE"
echo "============================================================"
EOF_RUNTIME

echo ""
echo "✔ bazzite-unraid runtime setup complete"

# # ============================================================
# # AUTOMATIC PASSWORD SETTING INSIDE CONTAINER
# # ============================================================
# echo " "
# echo "|****************************************************************"
# read -rsp "Enter password for root inside container: " ROOT_PASS
# echo
# read -rsp "Enter password for $HOST_USER inside container: " USER_PASS
# echo

# # Run password setting as root directly
# distrobox-enter "$CONTAINER_NAME" -- bash <<EOF_AUTOPASS
# set -e
# HOST_USER=\$(id -un)

# # Unlock accounts if needed
# sudo passwd -u root || true
# sudo passwd -u \$HOST_USER || true

# # Set root password
# echo "${ROOT_PASS}" | sudo passwd --stdin root 2>/dev/null || echo "${ROOT_PASS}" | sudo passwd root --stdin 2>/dev/null || true

# # Set $HOST_USER password
# echo "${USER_PASS}" | sudo passwd --stdin \$HOST_USER 2>/dev/null || echo "${USER_PASS}" | sudo passwd \$HOST_USER --stdin 2>/dev/null || true

# # Ensure passwordless sudo persists (run as root or with sudo)
# echo "$HOST_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-$HOST_USER-nopasswd >/dev/null
# sudo chmod 0440 /etc/sudoers.d/90-$HOST_USER-nopasswd
# EOF_AUTOPASS

# # Clear sensitive variables from memory
# unset USER_PASS
# echo "✓ Unset in-memory root and $HOST_USER passwords"
# echo "|****************************************************************"
# echo " "

echo "✔ You can now run Steam/XFCE/Sunshine as $HOST_USER inside the container"
} 2>&1 | tee -a "$LOG_FILE"

echo " "
echo "You will now be prompted to provide a password for user \"$HOST_USER\""
echo "After providing the password, you will be left at the prompt inside the distrobox."
echo "Type \"exit\" to leave the distrobox."
echo " "
distrobox enter $CONTAINER_NAME
# syntax=docker/dockerfile:1.4
FROM ghcr.io/ublue-os/arch-toolbox AS bazzite-unraid-xfce

COPY system_files /

# ============================================================
# PACKAGE INSTALLATION
# ============================================================
# Steam/Lutris/Wine installed separately so they use the 
# dependencies above and don't try to install their own.
# Display server (X11/Wayland) and DE packages are separated
# for easy switching between configurations.
# ============================================================

# Optimize pacman for parallel downloads
RUN sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# Sunshine repository
RUN echo -e "\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download" \
    >> /etc/pacman.conf

# Package updates & base system
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    # Update mirrors for better download reliability \
    pacman -Sy --noconfirm reflector && \
    reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && \
    # Update base packages \
    pacman -Syu --noconfirm && \
    # Install core build tools (needed for AUR and other builds) \
    pacman -S --noconfirm \
        base-devel \
        git \
        wget \
        curl \
        # FUSE support for AppImages \
        fuse2 \
        fuse3 \
        fuse-common \
        fuse-overlayfs \
        # Desktop integration (display-server agnostic) \
        xdg-utils \
        desktop-file-utils \
        xdg-user-dirs && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# Graphics drivers and libraries (display-server agnostic)
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm \
        mesa \
        mesa-utils \
        vulkan-tools \
        libva-mesa-driver \
        libva-utils \
        vdpauinfo \
        vulkan-mesa-layers \
        lib32-vulkan-mesa-layers \
        lib32-vulkan-radeon \
        xf86-video-amdgpu \
        intel-media-driver \
        rocm-opencl-runtime \
        rocm-hip-runtime && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# Audio stack (display-server agnostic)
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm \
        pipewire \
        pipewire-pulse \
        pipewire-alsa \
        pipewire-jack \
        wireplumber \
        lib32-pipewire \
        lib32-pipewire-jack \
        lib32-libpulse \
        openal \
        lib32-openal && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# System utilities (display-server agnostic)
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm \
        dbus \
        wmctrl \
        vim \
        nano \
        mc \
        tmux \
        hyfetch \
        fish \
        yad \
        # Additional libraries \
        wxwidgets-gtk3 \
        libbsd \
        lib32-libnm \
        ffmpegthumbnailer \
        libopenraw \
        poppler-glib \
        libgsf \
        # Fonts and locales \
        noto-fonts-cjk \
        glibc-locales && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# ============================================================
# GAMING APPLICATIONS
# ============================================================
# These packages work with both X11 and Wayland
# gamescope prefers Wayland but supports X11
# ============================================================

RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm \
        steam \
        lutris \
        gamemode \
        mangohud \
        lib32-mangohud \
        gamescope && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# ============================================================
# X11 DISPLAY SERVER PACKAGES
# ============================================================
# Replace this section with Wayland packages when switching
# to Wayland (e.g., wayland, wlroots, xwayland)
# ============================================================

RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm \
        xorg-server \
        xorg-xinit \
        xorg-xauth \
        xorg-xhost \
        xorg-xrandr \
        xorg-xdpyinfo \
        xorg-xwininfo \
        xterm \
        xdotool && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# ============================================================
# XFCE DESKTOP ENVIRONMENT
# ============================================================
# Replace this section with another DE (GNOME, KDE, etc.) or
# compositor (Sway, Hyprland, etc.) when switching away from XFCE
# ============================================================

RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm \
        xfce4 \
        xfce4-goodies \
        xfconf \
        xdg-desktop-portal-kde && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/* && \
    # Configure default XFCE startup \
    echo 'exec startxfce4' > /etc/skel/.xinitrc

# ============================================================
# SUNSHINE STREAMING SERVER
# ============================================================

RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --noconfirm lizardbyte/sunshine && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# ============================================================
# ADDITIONAL TOOLS
# ============================================================

RUN wget https://raw.githubusercontent.com/Shringe/LatencyFleX-Installer/main/install.sh -O /usr/bin/latencyflex && \
    sed -i 's@"dxvk.conf"@"/usr/share/latencyflex/dxvk.conf"@g' /usr/bin/latencyflex && \
    chmod +x /usr/bin/latencyflex

# ============================================================
# BUILD OPTIMIZATIONS FOR MULTI-CORE SYSTEM
# ============================================================

# Optimize makepkg for parallel builds
RUN sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/" /etc/makepkg.conf && \
    sed -i 's/-march=x86-64 -mtune=generic/-march=native -mtune=native/g' /etc/makepkg.conf && \
    sed -i 's/COMPRESSZST=(zstd -c -z -q -)/COMPRESSZST=(zstd -c -T0 -)/' /etc/makepkg.conf

# Configure Cargo for parallel builds (Rust packages)
RUN mkdir -p /root/.cargo && \
    printf '[build]\njobs = %d\n\n[profile.release]\nopt-level = 3\nlto = "thin"\n' "$(nproc)" > /root/.cargo/config.toml

# ============================================================
# AUR PACKAGES
# ============================================================
RUN cat /etc/makepkg.conf

# Create temporary build user for AUR installation
RUN useradd -m --shell=/bin/bash build && usermod -L build && \
    echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER build
WORKDIR /home/build

# Configure Cache & Cargo for build user
RUN mkdir -p /home/build/.cache && \
    sudo chown -R build:build /home/build/.cache && \
    mkdir -p ~/.cargo && \
    cat > ~/.cargo/config.toml <<EOF_CARGO
[build]
jobs = $(nproc)

[profile.release]
opt-level = 3
lto = "thin"
EOF_CARGO

# Remove all paru packages robustly
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/home/build/.cache \
    sudo pacman -Rdd --noconfirm paru-bin paru-bin-debug 2>/dev/null || true && \
    sudo rm -rf /usr/bin/paru /usr/lib/debug/usr/bin/paru* && \
    git clone https://aur.archlinux.org/paru.git && \
    cd paru && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf paru

RUN pacman -Q paru
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/home/build/.cache/paru \
    sudo mkdir -p /home/build/.cache/paru && \
    sudo chown -R build:build /home/build/.cache && \
    paru -S --noconfirm \
        aur/protontricks \
        aur/vkbasalt \
        aur/lib32-vkbasalt \
        aur/obs-vkcapture-git \
        aur/lib32-obs-vkcapture-git \
        aur/lib32-gperftools \
        aur/steamcmd \
        aur/appimagelauncher \
        aur/brave-bin

USER root
WORKDIR /

# Clean up build user immediately after AUR installation
RUN userdel -r build && \
    rm -drf /home/build && \
    sed -i '/build ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers && \
    sed -i '/root ALL=(ALL) NOPASSWD: ALL/d' /etc/sudoers && \
    rm -rf /home/build/.cache/*

# ============================================================
# SYSTEM CONFIGURATION
# ============================================================

# Set Sunshine capabilities
RUN setcap cap_sys_admin,cap_net_admin+ep /usr/bin/sunshine || true

# Create environment variable injection hook
RUN cat <<'EOF' > /etc/profile.d/bazzite-unraid-env.sh
#!/bin/sh
# Load host-injected environment variables
if [ -f "$HOME/.config/bazzite-unraid.env" ]; then
    set -a
    source "$HOME/.config/bazzite-unraid.env"
    set +a
fi
EOF

RUN chmod +x /etc/profile.d/bazzite-unraid-env.sh

# ============================================================
# USER SETUP
# ============================================================

ARG HOST_USER=bazzite

# Create required groups and main user
RUN getent group audio  || groupadd -r audio && \
    getent group video  || groupadd -r video && \
    getent group input  || groupadd -r input && \
    getent group uinput || groupadd -r uinput && \
    getent group wheel  || groupadd -r wheel && \
    useradd -m -G wheel,audio,video,input,uinput ${HOST_USER} && \
    echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers

# ============================================================
# FINAL OPTIMIZATION
# ============================================================

# Optimize makepkg for native architecture and clean Steam desktop entry
RUN sed -i 's@ (Runtime)@@g' /usr/share/applications/steam.desktop && \
    rm -rf /tmp/* /var/cache/pacman/pkg/*

# Note: Currently the sunshine.config must be configured to use X11 capture mode "capture = x11"
# For Wayland: Use "capture = wlroots" or "capture = pipewire" depending on compositor
# docker build --build-arg HOST_USER=$HOST_USER -t bazzite-unraid-xfce:latest .
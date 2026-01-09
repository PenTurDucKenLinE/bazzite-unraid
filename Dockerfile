# syntax=docker/dockerfile:1.4
FROM ghcr.io/ublue-os/arch-toolbox AS bazzite-unraid-xfce

COPY system_files /

# ============================================================
# PACKAGE INSTALLATION
# ============================================================
# Steam/Lutris/Wine installed separately so they use the 
# dependencies above and don't try to install their own.
# ============================================================

# Optimize pacman for parallel downloads
RUN sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# Sunshine repository
RUN echo -e "\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download" \
    >> /etc/pacman.conf

# Package updates & installations
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    # Update mirrors for better download reliability \
    pacman -Sy --noconfirm reflector && \
    reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && \
    # Update base packages \
    pacman -Syu --noconfirm && \
    # Install additional packages \
    pacman -S --noconfirm \
        # Build tools (needed for AUR and other builds) \
        base-devel \
        git \
        wget \
        curl \
        # FUSE support for AppImages \
        fuse2 \
        fuse3 \
        fuse-common \
        fuse-overlayfs \
        # Desktop integration
        xdg-utils \
        desktop-file-utils \
        # Graphics drivers and libraries \
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
        rocm-hip-runtime \
        # Audio stack \
        pipewire \
        pipewire-pulse \
        pipewire-alsa \
        pipewire-jack \
        wireplumber \
        lib32-pipewire \
        lib32-pipewire-jack \
        lib32-libpulse \
        openal \
        lib32-openal \
        # Desktop environment \
        xfce4 \
        xfce4-goodies \
        xfconf \
        # Desktop portal \
        xdg-desktop-portal-kde \
        xdg-user-dirs \
        # X.org components \
        xorg-server \
        xorg-xinit \
        xorg-xauth \
        xorg-xhost \
        xorg-xrandr \
        xorg-xdpyinfo \
        xorg-xwininfo \
        xterm \
        xdotool \
        # System utilities \
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
    # Gaming applications (installed after dependencies) \
    pacman -S --noconfirm \
        steam \
        lutris \
        gamemode \
        mangohud \
        lib32-mangohud \
        gamescope && \
    # Sunshine streaming server \
    pacman -S --noconfirm lizardbyte/sunshine && \
    # LatencyFleX installation \
    wget https://raw.githubusercontent.com/Shringe/LatencyFleX-Installer/main/install.sh -O /usr/bin/latencyflex && \
    sed -i 's@"dxvk.conf"@"/usr/share/latencyflex/dxvk.conf"@g' /usr/bin/latencyflex && \
    chmod +x /usr/bin/latencyflex && \
    # Cleanup \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

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

# Configure default XFCE startup
RUN echo 'exec startxfce4' > /etc/skel/.xinitrc

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
# docker build --build-arg HOST_USER=ABCXYZ123456 -t bazzite-unraid-xfce:latest .
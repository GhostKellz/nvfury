# nvfury Development Container
# Arch Linux with build tools for NVIDIA kernel module patch development
# NOTE: This container is for DEVELOPMENT/TESTING only
# It does NOT install modules - just builds and validates patches

FROM archlinux:latest

# Update and install build dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    curl \
    wget \
    clang \
    llvm \
    lld \
    llvm-libs \
    linux-headers \
    dkms \
    patch \
    diffutils \
    bc \
    pahole \
    python \
    perl \
    && pacman -Scc --noconfirm

# Link Zig (mounted from host)
RUN ln -sf /opt/zig-0.16.0-dev/zig /usr/local/bin/zig

# Create workspace
WORKDIR /workspace/nvfury

# Environment
ENV PATH="/opt/zig-0.16.0-dev:${PATH}"
ENV LLVM=1
ENV CC=clang
ENV LD=ld.lld

# Don't run as root for safety (can't accidentally modprobe)
RUN useradd -m -s /bin/bash dev
# But we need to be able to write to workspace
RUN chown -R dev:dev /workspace || true

CMD ["/bin/bash"]

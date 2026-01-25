# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>
pkgname=nvfury
pkgver=1.0.0
pkgrel=1
pkgdesc="NVIDIA Open Kernel Module Forge - Build optimized drivers with gaming patches"
arch=('x86_64')
url="https://github.com/ghostkellz/nvfury"
license=('MIT')
depends=('glibc')
makedepends=('zig>=0.14')
optdepends=(
    'dkms: Automatic kernel module rebuilds'
    'linux-headers: Required for driver builds'
    'git: Fetch driver sources from GitHub'
    'ccache: Speed up rebuilds'
    'mokutil: SecureBoot key enrollment'
    'sbsigntools: Module signing for SecureBoot'
    'libnotify: Desktop notifications for updates'
)
backup=('etc/modprobe.d/nvfury.conf')
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast
}

package() {
    cd "$pkgname-$pkgver"

    # Binary
    install -Dm755 zig-out/bin/nvfury "$pkgdir/usr/bin/nvfury"

    # Man page
    install -Dm644 man/nvfury.1 "$pkgdir/usr/share/man/man1/nvfury.1"

    # Shell completions
    install -Dm644 completions/nvfury.bash "$pkgdir/usr/share/bash-completion/completions/nvfury"
    install -Dm644 completions/nvfury.zsh "$pkgdir/usr/share/zsh/site-functions/_nvfury"
    install -Dm644 completions/nvfury.fish "$pkgdir/usr/share/fish/vendor_completions.d/nvfury.fish"

    # Patches
    install -dm755 "$pkgdir/usr/share/nvfury/patches"
    install -Dm644 patches/*.patch "$pkgdir/usr/share/nvfury/patches/"
    install -Dm644 patches/README.md "$pkgdir/usr/share/nvfury/patches/README.md"

    # Systemd user units
    install -Dm644 systemd/nvfury-update.service "$pkgdir/usr/lib/systemd/user/nvfury-update.service"
    install -Dm644 systemd/nvfury-update.timer "$pkgdir/usr/lib/systemd/user/nvfury-update.timer"

    # Documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 docs/*.md "$pkgdir/usr/share/doc/$pkgname/"

    # License
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}

post_install() {
    echo ":: nvfury installed successfully!"
    echo ""
    echo "Quick start:"
    echo "  nvfury build              # Build optimized NVIDIA modules"
    echo "  sudo nvfury install --dkms  # Install with DKMS"
    echo "  sudo nvfury tune gaming   # Apply gaming preset"
    echo ""
    echo "Enable automatic update checking:"
    echo "  systemctl --user enable --now nvfury-update.timer"
    echo ""
    echo "See 'man nvfury' for full documentation."
}

post_upgrade() {
    post_install
}

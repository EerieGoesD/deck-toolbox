pkgname=deck-toolbox
pkgver=1.1.2
pkgrel=1
pkgdesc="One-click maintenance and troubleshooting scripts for the Steam Deck"
arch=('x86_64')
url="https://github.com/EerieGoesD/deck-toolbox"
license=('MIT')
depends=('webkit2gtk-4.1' 'gtk3')

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

build() {
  cd "$BASEDIR"
  source "$HOME/.cargo/env" 2>/dev/null || true
  cargo tauri build --no-bundle
}

package() {
  cd "$BASEDIR"

  # Binary
  install -Dm755 "src-tauri/target/release/deck-toolbox" "$pkgdir/usr/bin/deck-toolbox"

  # Desktop entry
  install -Dm644 "io.github.EerieGoesD.DeckToolbox.desktop" "$pkgdir/usr/share/applications/io.github.EerieGoesD.DeckToolbox.desktop"

  # Icon
  install -Dm644 "icons/io.github.EerieGoesD.DeckToolbox.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/io.github.EerieGoesD.DeckToolbox.png"

  # Metainfo
  install -Dm644 "io.github.EerieGoesD.DeckToolbox.metainfo.xml" "$pkgdir/usr/share/metainfo/io.github.EerieGoesD.DeckToolbox.metainfo.xml"

  # Shell scripts (as resources)
  install -dm755 "$pkgdir/usr/share/deck-toolbox/scripts"
  install -m755 src-tauri/resources/scripts/*.sh "$pkgdir/usr/share/deck-toolbox/scripts/"
}

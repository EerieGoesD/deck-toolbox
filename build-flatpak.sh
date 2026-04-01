#!/bin/bash
# Build Deck Toolbox as a .flatpak bundle for sideloading on Steam Deck
# Run this on the Steam Deck in Desktop Mode
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/flatpak/build"
STAGING="$REPO_DIR/flatpak/staging"
MANIFEST="$REPO_DIR/flatpak/io.github.EerieGoesD.DeckToolbox.yml"

echo "=== Deck Toolbox Flatpak Builder ==="
echo ""

# Step 1: Build the Tauri binary
echo "[1/4] Building Tauri binary..."
source "$HOME/.cargo/env" 2>/dev/null || true
cargo tauri build --no-bundle
echo ""

# Step 2: Install flatpak-builder if needed
if ! command -v flatpak-builder &>/dev/null; then
  echo "[2/4] Installing flatpak-builder..."
  sudo steamos-readonly disable
  sudo pacman -S --needed --noconfirm flatpak-builder
  sudo steamos-readonly enable
else
  echo "[2/4] flatpak-builder already installed."
fi
echo ""

# Step 3: Install SDK if needed
echo "[3/4] Ensuring Flatpak SDK is available..."
flatpak install --user --noninteractive flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08 2>/dev/null || true
echo ""

# Step 4: Stage files and build
echo "[4/4] Building Flatpak bundle..."
rm -rf "$STAGING"
mkdir -p "$STAGING/scripts"

cp "$REPO_DIR/src-tauri/target/release/deck-toolbox" "$STAGING/deck-toolbox"
cp "$REPO_DIR/io.github.EerieGoesD.DeckToolbox.desktop" "$STAGING/"
cp "$REPO_DIR/icons/io.github.EerieGoesD.DeckToolbox.png" "$STAGING/"
cp "$REPO_DIR/io.github.EerieGoesD.DeckToolbox.metainfo.xml" "$STAGING/"
cp "$REPO_DIR/src-tauri/resources/scripts/"*.sh "$STAGING/scripts/"

# Update manifest paths to use staging dir
cd "$STAGING"
cp "$MANIFEST" ./manifest.yml
sed -i "s|path: deck-toolbox|path: $STAGING/deck-toolbox|g" manifest.yml
sed -i "s|path: io.github.EerieGoesD.DeckToolbox.desktop|path: $STAGING/io.github.EerieGoesD.DeckToolbox.desktop|g" manifest.yml
sed -i "s|path: io.github.EerieGoesD.DeckToolbox.png|path: $STAGING/io.github.EerieGoesD.DeckToolbox.png|g" manifest.yml
sed -i "s|path: io.github.EerieGoesD.DeckToolbox.metainfo.xml|path: $STAGING/io.github.EerieGoesD.DeckToolbox.metainfo.xml|g" manifest.yml
sed -i "s|path: scripts|path: $STAGING/scripts|g" manifest.yml

# Build flatpak
flatpak-builder --force-clean --user --repo="$BUILD_DIR/repo" "$BUILD_DIR/app" manifest.yml

# Create .flatpak bundle
flatpak build-bundle "$BUILD_DIR/repo" "$REPO_DIR/DeckToolbox.flatpak" io.github.EerieGoesD.DeckToolbox

echo ""
echo "=== Done! ==="
echo "Flatpak bundle created: $REPO_DIR/DeckToolbox.flatpak"
echo ""
echo "To install: double-click DeckToolbox.flatpak in the file manager"
echo "Or run: flatpak install --user DeckToolbox.flatpak"

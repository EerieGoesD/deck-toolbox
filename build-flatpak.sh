#!/bin/bash
# Build Deck Toolbox as a .flatpak bundle for sideloading on Steam Deck
# Run this on the Steam Deck in Desktop Mode
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
FLATPAK_DIR="$REPO_DIR/flatpak"
MANIFEST="$FLATPAK_DIR/io.github.EerieGoesD.DeckToolbox.yml"

echo "=== Deck Toolbox Flatpak Builder ==="
echo ""

# Step 1: Install flatpak-builder and python if needed
echo "[1/5] Checking dependencies..."
NEED_INSTALL=""
command -v flatpak-builder &>/dev/null || NEED_INSTALL="flatpak-builder $NEED_INSTALL"
command -v python3 &>/dev/null || NEED_INSTALL="python $NEED_INSTALL"

if [[ -n "$NEED_INSTALL" ]]; then
  echo "Installing: $NEED_INSTALL"
  sudo steamos-readonly disable
  sudo pacman -S --needed --noconfirm $NEED_INSTALL
  sudo steamos-readonly enable
else
  echo "All dependencies installed."
fi
echo ""

# Step 2: Install SDK
echo "[2/5] Ensuring Flatpak SDK is available..."
flatpak install --user --noninteractive flathub org.gnome.Platform//49 org.gnome.Sdk//49 2>/dev/null || true
echo ""

# Step 3: Generate cargo-sources.json
echo "[3/5] Generating cargo dependency sources..."
if [[ ! -f "$FLATPAK_DIR/flatpak-cargo-generator.py" ]]; then
  curl -sL "https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/master/cargo/flatpak-cargo-generator.py" \
    -o "$FLATPAK_DIR/flatpak-cargo-generator.py"
fi
python3 "$FLATPAK_DIR/flatpak-cargo-generator.py" \
  "$REPO_DIR/src-tauri/Cargo.lock" \
  -o "$FLATPAK_DIR/cargo-sources.json"
echo "Generated cargo-sources.json with $(grep -c '"type"' "$FLATPAK_DIR/cargo-sources.json") sources."
echo ""

# Step 4: Build Flatpak
echo "[4/5] Building Flatpak (compiling from source inside sandbox)..."
echo "This will take several minutes on first build..."
cd "$FLATPAK_DIR"
flatpak-builder --force-clean --user --repo="$FLATPAK_DIR/repo" "$FLATPAK_DIR/build" "$MANIFEST"
echo ""

# Step 5: Create bundle
echo "[5/5] Creating .flatpak bundle..."
flatpak build-bundle "$FLATPAK_DIR/repo" "$REPO_DIR/DeckToolbox.flatpak" io.github.EerieGoesD.DeckToolbox

echo ""
echo "=== Done! ==="
echo "Flatpak bundle created: $REPO_DIR/DeckToolbox.flatpak"
echo ""
echo "To install: double-click DeckToolbox.flatpak in the file manager"
echo "Or run: flatpak install --user $REPO_DIR/DeckToolbox.flatpak"

#!/bin/bash
# Deck Toolbox installer for Steam Deck / SteamOS
set -e

APPIMAGE="$(find "$(dirname "$0")" -maxdepth 1 -name '*.AppImage' | head -1)"

if [[ -z "$APPIMAGE" ]]; then
  echo "Error: No .AppImage file found in the same directory as this script."
  echo "Download the AppImage from GitHub Releases and place it next to this script."
  exit 1
fi

APP_DIR="$HOME/.local/share/deck-toolbox"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons"

echo "Installing Deck Toolbox..."

mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# Copy AppImage
cp "$APPIMAGE" "$APP_DIR/deck-toolbox.AppImage"
chmod +x "$APP_DIR/deck-toolbox.AppImage"

# Create symlink in PATH
ln -sf "$APP_DIR/deck-toolbox.AppImage" "$BIN_DIR/deck-toolbox"

# Create desktop entry
cat > "$DESKTOP_DIR/io.github.EerieGoesD.DeckToolbox.desktop" << EOF
[Desktop Entry]
Name=Deck Toolbox
Comment=One-click maintenance and troubleshooting scripts for the Steam Deck
Exec=$APP_DIR/deck-toolbox.AppImage
Icon=io.github.EerieGoesD.DeckToolbox
Type=Application
Categories=Utility;System;
Terminal=false
StartupWMClass=deck-toolbox
EOF

# Copy icon if available
if [[ -f "$(dirname "$0")/icons/io.github.EerieGoesD.DeckToolbox.png" ]]; then
  cp "$(dirname "$0")/icons/io.github.EerieGoesD.DeckToolbox.png" "$ICON_DIR/io.github.EerieGoesD.DeckToolbox.png"
fi

echo ""
echo "Deck Toolbox installed!"
echo "You can find it in your application menu or run: deck-toolbox"

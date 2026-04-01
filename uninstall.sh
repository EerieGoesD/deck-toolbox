#!/bin/bash
# Deck Toolbox uninstaller
set -e

echo "Uninstalling Deck Toolbox..."

rm -rf "$HOME/.local/share/deck-toolbox"
rm -f "$HOME/.local/bin/deck-toolbox"
rm -f "$HOME/.local/share/applications/io.github.EerieGoesD.DeckToolbox.desktop"
rm -f "$HOME/.local/share/icons/io.github.EerieGoesD.DeckToolbox.png"

echo "Deck Toolbox uninstalled."

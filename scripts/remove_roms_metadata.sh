#!/bin/bash
# Removes downloaded media and gamelist metadata for ROMs.

echo "Removing downloaded media..."
rm -rf /run/media/deck/EmuDeck/Emulation/tools/downloaded_media/

echo "Removing EmuDeck gamelist.xml files..."
find ~/.config/EmuDeck/backend/configs/emulationstation/gamelists/ -name "gamelist.xml" -delete 2>/dev/null

echo "Removing ES-DE gamelist.xml files..."
find ~/ES-DE/gamelists/ -name "gamelist.xml" -delete 2>/dev/null

echo "Done. Media and metadata cleared."

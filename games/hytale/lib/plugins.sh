#!/bin/bash

install_sourcequery() {
    if [ "$ENABLE_SOURCE_QUERY_SUPPORT" = "1" ]; then
        logger info "Source Query support enabled, checking for plugin..."

        if [ ! -d "$MODS_FOLDER" ]; then
            logger warn "Creating mods directory..."
            mkdir -p $MODS_FOLDER
        fi

        if [ -d "$MODS_FOLDER" ] && { [ ! -r "$MODS_FOLDER" ] || [ ! -w "$MODS_FOLDER" ] || [ ! -x "$MODS_FOLDER" ]; }; then
            logger warn "Fixing permissions on directory $MODS_FOLDER..."
            chmod 755 "$MODS_FOLDER"
        fi

        logger info "Downloading latest hytale-sourcequery plugin..."
        local LATEST_URL=$(curl -sSL https://api.github.com/repos/physgun-com/hytale-sourcequery/releases/latest | jq -r '.assets[0].browser_download_url // empty')

        if [ -n "$LATEST_URL" ]; then
            if curl -sSL -o "${MODS_FOLDER}/hytale-sourcequery.jar" "$LATEST_URL"; then
                logger success "Successfully downloaded hytale-sourcequery plugin"
            else
                logger error "Failed to download hytale-sourcequery plugin"
            fi
        fi
    fi
}
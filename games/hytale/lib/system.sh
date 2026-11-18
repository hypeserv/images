#!/bin/bash

create_system_files() {
    # Create version file
    if [ ! -f "$VERSION_FILE" ]; then
        logger info "Creating version check file..."
        touch $VERSION_FILE
    fi

    if [ ! -f "$PATCHLINE_CACHE_FILE" ]; then
        logger info "Creating patchline cache file..."
        touch $PATCHLINE_CACHE_FILE
    fi
}

ensure_system_file_permissions() {
    #Fix system permissions
    if [ -f "$VERSION_FILE" ] && { [ ! -r "$VERSION_FILE" ] || [ ! -w "$VERSION_FILE" ]; }; then
        logger warn "Fixing permissions on $VERSION_FILE..."
        chmod 644 "$VERSION_FILE"
    fi
    if [ -f "$PATCHLINE_CACHE_FILE" ] && { [ ! -r "$PATCHLINE_CACHE_FILE" ] || [ ! -w "$PATCHLINE_CACHE_FILE" ]; }; then
        logger warn "Fixing permissions on $PATCHLINE_CACHE_FILE..."
        chmod 644 "$PATCHLINE_CACHE_FILE"
    fi
    if [ -f "$DOWNLOAD_CRED_FILE" ] && { [ ! -r "$DOWNLOAD_CRED_FILE" ] || [ ! -w "$DOWNLOAD_CRED_FILE" ]; }; then
        logger warn "Fixing permissions on $DOWNLOAD_CRED_FILE..."
        chmod 644 "$DOWNLOAD_CRED_FILE"
    fi
    if [ -f "$AUTH_CACHE_FILE" ] && { [ ! -r "$AUTH_CACHE_FILE" ] || [ ! -w "$AUTH_CACHE_FILE" ]; }; then
        logger warn "Fixing permissions on $AUTH_CACHE_FILE..."
        chmod 644 "$AUTH_CACHE_FILE"
    fi
}

detect_architecture() {
    local ARCH=$(uname -m)
    logger info "Platform: $ARCH"

    case "$ARCH" in
        x86_64)
            DOWNLOADER="./hytale-downloader-linux-amd64"
            ;;
        aarch64|arm64)
            DOWNLOADER="./hytale-downloader-linux-arm64"
            ;;
        *)
            logger error "Unsupported architecture: $ARCH"
            logger info "Supported architectures: x86_64 (amd64), aarch64/arm64"
            exit 1
            ;;
    esac
}

setup_environment() {
    # Get and export timezone
    export TZ=${TZ:-UTC}

    # Get and export the internal docker ip
    export INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')

    # Goto working directory
    cd /home/container || exit 1
}

setup_backup_directory() {
    if [ ! -d "backup" ]; then
        logger info "Backup directory does not exist. Creating it..."
        mkdir -p backup
        if [ $? -ne 0 ]; then
            logger error "Failed to create backup directory: /backup"
            exit 1
        fi
    fi
    chmod -R 755 backup
}

enforce_permissions() {
    if [ "$ENFORCE_PERMISSIONS" = "1" ]; then
        logger warn "Enforcing permissions... This might take a while. Please be patient."
        find . -type d -exec chmod 755 {} \;
        find . -type f \
            ! -name "hytale-downloader-linux-amd64" \
            ! -name "hytale-downloader-linux-arm64" \
            ! -name "start.sh" \
            -exec chmod 644 {} \;
        logger success "Permissions enforced (files: 644, folders: 755)"
    fi
}
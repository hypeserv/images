# Setup colors
RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" RESET=""
if [ -t 1 ] || { [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; }; then
    # Helper to get color code (tput or ANSI fallback)
    if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
        _c() { tput setaf "$1"; }
        _r() { tput sgr0; }
    else
        _c() { printf '\033[0;3%dm' "$1"; }
        _r() { printf '\033[0m'; }
    fi

    RED=$(_c 1) GREEN=$(_c 2) YELLOW=$(_c 3)
    BLUE=$(_c 4) MAGENTA=$(_c 5) CYAN=$(_c 6)
    RESET=$(_r)
    unset -f _c _r
fi

#Function to print colored text
printc() {
    local text="$1"

    # Replace tags with color codes (or empty string if not supported)
    text="${text//\{RED\}/$RED}"
    text="${text//\{GREEN\}/$GREEN}"
    text="${text//\{YELLOW\}/$YELLOW}"
    text="${text//\{BLUE\}/$BLUE}"
    text="${text//\{MAGENTA\}/$MAGENTA}"
    text="${text//\{CYAN\}/$CYAN}"
    text="${text//\{RESET\}/$RESET}"
    printf "%b\n" "$text"
}

# Logger function to print messages with different colors based on level
logger() {
    local level="$1"
    local message="$2"

    case "${level^^}" in
        "INFO")    printc "{BLUE}ℹ $message{RESET}" ;;
        "WARN")    printc "{YELLOW}⚠ $message{RESET}" ;;
        "ERROR")   printc "{RED}⨯ $message{RESET}" ;;
        "SUCCESS") printc "{GREEN}✓ $message{RESET}" ;;
        *)         printc "$message" ;;
    esac
}

# Function to extract downloaded server files
extract_server_files() {
    logger info "Extracting server files..."
    SERVER_ZIP="server.zip"

    if [ -f "$SERVER_ZIP" ]; then
        logger success "Found server archive: $SERVER_ZIP"

        # Extract to current directory
        unzip -o "$SERVER_ZIP"

        if [ $? -ne 0 ]; then
            logger error "Failed to extract $SERVER_ZIP"
            exit 1
        fi

        logger success "Extraction completed successfully."

        # Move contents from Server folder to current directory
        if [ -d "Server" ]; then
            logger info "Moving server files from Server directory..."
            cp -rf Server/* .
            rm -rf ./Server
            logger success "Server files moved to root directory."
        fi

        # Clean up the zip file
        logger info "Cleaning up archive file..."
        rm "$SERVER_ZIP"
        logger success "Archive removed."
    else
        logger error "Server archive not found at $SERVER_ZIP"
        exit 1
    fi
}
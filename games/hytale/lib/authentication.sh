# Function to check if cached tokens exist
check_cached_tokens() {
    if [ -f "$AUTH_CACHE_FILE" ]; then
        # Check if jq is available
        if ! command -v jq &> /dev/null; then
            logger warn "jq not found, cannot use cached tokens"
            return 1
        fi

        # Validate JSON format
        if ! jq empty "$AUTH_CACHE_FILE" 2>/dev/null; then
            logger warn "Invalid cached token file, removing..."
            rm "$AUTH_CACHE_FILE"
            return 1
        fi

		# Check if required keys exist
        REFRESH_TOKEN_EXISTS=$(jq -r 'has("refresh_token")' "$AUTH_CACHE_FILE")
        PROFILE_UUID_EXISTS=$(jq -r 'has("profile_uuid")' "$AUTH_CACHE_FILE")

        if [ "$REFRESH_TOKEN_EXISTS" != "true" ] || [ "$PROFILE_UUID_EXISTS" != "true" ]; then
            logger warn "Cached token file missing required keys, removing..."
            rm "$AUTH_CACHE_FILE"
            return 1
        fi

        logger success "Found cached authentication tokens"
        return 0
    fi
    return 1
}



# Function to load cached tokens (refresh_token + profile_uuid only)
load_cached_tokens() {
    REFRESH_TOKEN=$(jq -r '.refresh_token' "$AUTH_CACHE_FILE")
    PROFILE_UUID=$(jq -r '.profile_uuid' "$AUTH_CACHE_FILE")

    # Validate required tokens are present
    if [ -z "$REFRESH_TOKEN" ] || [ "$REFRESH_TOKEN" = "null" ] || \
       [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
        logger error "Incomplete cached tokens, re-authenticating..."
        rm "$AUTH_CACHE_FILE"
        return 1
    fi

    logger success "Loaded cached refresh token + profile UUID"
    return 0
}



# Function to refresh access token using cached refresh token
refresh_access_token() {
    logger info "Refreshing access token..."

    TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=hytale-server" \
      -d "grant_type=refresh_token" \
      -d "refresh_token=$REFRESH_TOKEN")

    ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
    if [ -n "$ERROR" ]; then
        logger error "Failed to refresh access token: $ERROR"
        return 1
    fi

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    NEW_REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')

    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        logger error "No access token in refresh response"
        return 1
    fi

    # Update refresh token if a new one was provided
    if [ -n "$NEW_REFRESH_TOKEN" ] && [ "$NEW_REFRESH_TOKEN" != "null" ]; then
        REFRESH_TOKEN="$NEW_REFRESH_TOKEN"
    fi

    logger success "Access token refreshed"
    return 0
}



# Function to create a new game session
create_game_session() {
    logger info "Creating game server session..."

    SESSION_RESPONSE=$(curl -s -X POST "https://sessions.hytale.com/game-session/new" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"uuid\": \"$PROFILE_UUID\"}")

    # Validate JSON response
    if ! echo "$SESSION_RESPONSE" | jq empty 2>/dev/null; then
        logger error "Invalid JSON response from game session creation"
        logger info "Response: $SESSION_RESPONSE"
        return 1
    fi

    # Extract session and identity tokens
    SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken')
    IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken')

    if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ]; then
        logger error "Failed to create game server session"
        logger info "Response: $SESSION_RESPONSE"
        return 1
    fi

    logger success "Game server session created successfully!"
    return 0
}

# Function to save authentication tokens (refresh_token + profile_uuid only)
save_auth_tokens() {

    # Create auth cache file (only in standard mode, not GSP mode)
    if [ ! -f "$AUTH_CACHE_FILE" ]; then
        logger info "Creating auth cache file..."
        touch $AUTH_CACHE_FILE
    fi

    cat > "$AUTH_CACHE_FILE" << EOF
{
  "refresh_token": "$REFRESH_TOKEN",
  "profile_uuid": "$PROFILE_UUID",
  "timestamp": $(date +%s)
}
EOF
    logger info "Refresh token cached for future use"
}



# Function to perform full authentication
perform_authentication() {
    logger info "Obtaining authentication tokens..."

    # Step 1: Request device code
    AUTH_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/device/auth" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=hytale-server" \
      -d "scope=openid offline auth:server")

    # Extract device_code and verification_uri_complete using jq
    DEVICE_CODE=$(echo "$AUTH_RESPONSE" | jq -r '.device_code')
    VERIFICATION_URI=$(echo "$AUTH_RESPONSE" | jq -r '.verification_uri_complete')
    POLL_INTERVAL=$(echo "$AUTH_RESPONSE" | jq -r '.interval')

    # Display authentication banner
    echo " "
    printc "{MAGENTA}╔═════════════════════════════════════════════════════════════════════════════╗"
    printc "{MAGENTA}║                       {BLUE}HYTALE SERVER AUTHENTICATION REQUIRED                 {MAGENTA}║"
    printc "{MAGENTA}╠═════════════════════════════════════════════════════════════════════════════╣"
    printc "{MAGENTA}║                                                                             ║"
    printc "{MAGENTA}║  {CYAN}Please authenticate the server by visiting the following URL:              {MAGENTA}║"
    printc "{MAGENTA}║                                                                             ║"
    printc "{MAGENTA}║  {YELLOW}$VERIFICATION_URI  {MAGENTA}║"
    printc "{MAGENTA}║                                                                             ║"
    printc "{MAGENTA}║  {CYAN}1. Click the link above or copy it to your browser                         {MAGENTA}║"
    printc "{MAGENTA}║  {CYAN}2. Sign in with your Hytale account                                        {MAGENTA}║"
    printc "{MAGENTA}║  {CYAN}3. Authorize the server                                                    {MAGENTA}║"
    printc "{MAGENTA}║                                                                             ║"
    printc "{MAGENTA}║  {CYAN}Waiting for authentication...                                              {MAGENTA}║"
    printc "{MAGENTA}║                                                                             ║"
    printc "{MAGENTA}╚═════════════════════════════════════════════════════════════════════════════╝"
    printc " "

    # Step 2: Poll for access token
    ACCESS_TOKEN=""
    while [ -z "$ACCESS_TOKEN" ]; do
        sleep $POLL_INTERVAL

        TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=hytale-server" \
          -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
          -d "device_code=$DEVICE_CODE")

        # Check if we got an error
        ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

        if [ "$ERROR" = "authorization_pending" ]; then
            logger info "Still waiting for authentication..."
            continue
        elif [ -n "$ERROR" ]; then
            logger error "Authentication error: $ERROR"
            exit 1
        else
            # Successfully authenticated
            ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
            REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
            echo ""
            logger success "Authentication successful!"
            echo ""
        fi
    done

    # Fetch available game profiles
    logger info "Fetching game profiles..."

    PROFILES_RESPONSE=$(curl -s -X GET "https://account-data.hytale.com/my-account/get-profiles" \
      -H "Authorization: Bearer $ACCESS_TOKEN")

    # Check if profiles list is empty
    PROFILES_COUNT=$(echo "$PROFILES_RESPONSE" | jq '.profiles | length')

    if [ "$PROFILES_COUNT" -eq 0 ]; then
        logger error "No game profiles found. You need to purchase Hytale to run a server."
        exit 1
    fi

    # Select profile based on GAME_PROFILE variable
    if [ -n "$GAME_PROFILE" ]; then
        # User specified a profile username, find matching UUID
        logger info "Looking for profile: $GAME_PROFILE"
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r ".profiles[] | select(.username == \"$GAME_PROFILE\") | .uuid")

        if [ -z "$PROFILE_UUID" ] || [ "$PROFILE_UUID" = "null" ]; then
            logger error "Profile '$GAME_PROFILE' not found."
            logger info "Available profiles:"
            logger success "$PROFILES_RESPONSE" | jq -r '.profiles[] | "  - \(.username)"'
            exit 1
        fi

        logger success "Using profile: $GAME_PROFILE (UUID: $PROFILE_UUID)"
    else
        # Use first profile from the list
        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].uuid')
        PROFILE_USERNAME=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].username')

        logger success "Using default profile: $PROFILE_USERNAME (UUID: $PROFILE_UUID)"
    fi

    echo ""

    # Save refresh token + profile for future use
    save_auth_tokens

    # Create game server session
    if ! create_game_session; then
        exit 1
    fi
    echo ""
}
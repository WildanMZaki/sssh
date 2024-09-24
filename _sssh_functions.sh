
_error() {
    echo -e "${RED}$1${NC}"
}

_success() {
    echo -e "${GREEN}$1${NC}"
}

_warning() {
    echo -e "${YELLOW}$1${NC}"
}

_info() {
    echo -e "${CYAN}$1${NC}"
}

# Function to prompt for input with a default value
_ask() {
    local question="$1"
    local default_value="$2"

    # Build the prompt message
    if [ -n "$default_value" ]; then
        prompt="${question} (${default_value}):"
    else
        prompt="${question}:"
    fi

    # Use 'read -p' to show prompt and get input in the same line, ensuring flush
    read -r -p "$prompt" input

    # Return input if given, otherwise return the default value
    if [ -z "$input" ]; then
        echo "$default_value"
    else
        echo "$input"
    fi
}

# Function to confirm an action with a default value of 'y'
_confirm() {
    local question="$1"
    local default="y"

    response=$(_ask "$question" "$default")

    # Check if the response starts with 'y' or 'Y'
    if [[ "$response" =~ ^[yY] ]]; then
        return 0  # Confirmed
    else
        return 1  # Not confirmed
    fi
}

# Function to detect a PEM file in the current directory
detect_pem_file() {
    pem_files=($(find . -maxdepth 1 -name "*.pem" | sort))  # Sort the list for consistent order

    if [ ${#pem_files[@]} -eq 0 ]; then
        # No PEM files found
        echo ""
    elif [ ${#pem_files[@]} -eq 1 ]; then
        # Only one PEM file found, just return the basename
        echo "$(basename "${pem_files[0]}")"
    else
        # Multiple PEM files found, format them for display
        for i in "${!pem_files[@]}"; do
            pem_files[i]=$(basename "${pem_files[i]}")
        done

        # Multiple PEM files found, use 'select' to prompt the user to choose
        PS3="Select a PEM file by number: "  # Custom prompt

        # Use 'select' to generate a menu
        select selected_pem in "${pem_files[@]}"; do
            if [ -n "$selected_pem" ]; then
                # A valid selection was made, return the selected file
                echo "${selected_pem}"
                break
            fi
        done
    fi
}

# Function to get the last connected SSH host
get_last_ssh() {
    if [ -f "$CONFIG_FILE" ]; then
        jq -r '.last_host // empty' "$CONFIG_FILE"
    else
        echo ""
    fi
}

# Function to save the current SSH host as the last connected host
save_last_ssh() {
    local host="$1"
    
    # Update only the last_host property without removing hosts
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg host "$host" '.last_host = $host' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        # If the config file doesn't exist, create it with the last_host
        jq -n --arg host "$host" '{last_host: $host, hosts: []}' > "$CONFIG_FILE"
    fi
}

# Function to save SSH host to the history (last 10 hosts)
save_host_to_list() {
    local host="$1"
    
    # Load existing history, or create an empty array if none exists
    local hosts=$(jq -r '.hosts // []' "$CONFIG_FILE" 2>/dev/null)

    # Append the new host to the array
    if [ -n "$host" ]; then
        updated_hosts=$(echo "$hosts" | jq --arg host "$host" '. + [$host] | unique | .[-10:]')
        # Save the updated host list to the config file
        jq --argjson hosts "$updated_hosts" '.hosts = $hosts' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
}

# Function to list the last connected hosts
list_hosts() {
    local latest=$(get_last_ssh)
    local hosts=$(jq -r '.hosts[]' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$hosts" ]; then
        _info "No hosts available."
    else
        _info "Connected Hosts:"
        local output=()  # Initialize an array to hold the formatted lines
        
        # Read the hosts line by line
        while IFS= read -r host; do
            # Trim any leading/trailing whitespace from host
            host=$(echo "$host" | xargs)

            # Prepare the output line
            line="$host"
            # Check if the host matches the latest host
            if [[ "$host" == "$latest" ]]; then
                line="$line (latest)"
            fi
            output+=("$line")  # Add the formatted line to the array
        done <<< "$hosts"  # Pass the hosts variable directly to the loop

        # Print all output lines with counter
        for i in "${!output[@]}"; do
            echo "  $((i + 1)). ${output[i]}"  # Print the index + 1 as the counter
        done
    fi
}

# Function to reconnect to a host by index
connect_by_index() {
    local index=$1
    local host=$(jq -r ".hosts[$index-1]" "$CONFIG_FILE" 2>/dev/null)
    
    if [ -z "$host" ]; then
        _error "Error: No host found at index $index."
    else
        _info "Connecting to $host..."
        create_connection "$host"
    fi
}

# Function to remove a host by index
remove_host() {
    local index=$1

    # Check if the config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        _error "No hosts available to remove."
        return
    fi

    # Get the existing hosts array
    local hosts=$(jq -c '.hosts' "$CONFIG_FILE")
    
    if [ "$(echo "$hosts" | jq 'length')" -eq 0 ]; then
        _error "No hosts available to remove."
        return
    fi

    # Get the host to remove based on index
    local host_to_remove=$(echo "$hosts" | jq -r ".[$((index - 1))]")

    if [ -z "$host_to_remove" ]; then
        _error "Error: No host found at index $index."
    else
        # Remove the host from the array
        local updated_hosts=$(echo "$hosts" | jq "del(.[($index - 1)])")

        # Update the config file
        jq --argjson hosts "$updated_hosts" '.hosts = $hosts' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        _success "Removed host: $host_to_remove"
    fi
}

# Clear the SSH host history and cache
clear_data() {
    # If --force is found, skip confirmation
    if [ "$force_mode" = true ]; then
        rm -f "$CONFIG_FILE"
        rm -f "$HISTORY_FILE"
        _success "History and cache cleared."
    else
        # Otherwise, ask for confirmation
        if _confirm "Are you sure you want to clear the SSH host history and cache?"; then
            rm -f "$CONFIG_FILE"
            rm -f "$HISTORY_FILE"
            _success "History and cache cleared."
        else
            _info "Clear operation canceled."
        fi
    fi
}


show_history() {
    if [ -f "$HISTORY_FILE" ]; then
        tail "$@" "$HISTORY_FILE"
    else
        echo "No SSH history available."
    fi
}

# Log the SSH connection to the history file
log_history() {
    local host="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "Logged in at $timestamp to $host" >> "$HISTORY_FILE"
}

# Create connection
create_connection () {
    local host="$1"
    local pem_file=$(detect_pem_file)
    save_last_ssh "$host"
    if [ -n "$pem_file" ]; then
        _info "Using detected PEM file: $pem_file"
        ssh -i "$pem_file" "$host"
    else
        ssh "$host"
    fi
    log_history "$host"
}
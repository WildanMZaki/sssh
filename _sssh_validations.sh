# Function to validate if jq is installed
validate_jq() {
    if ! command -v jq &> /dev/null; then
        _error "Error: jq is required but not installed."
        exit 1
    fi
}

# Function to validate SSH host format
validate_ssh_host() {
    local host="$1"
    
    # Regular expression to match username@hostnameOrIPAddress
    if [[ "$host" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$ ]]; then
        return 0  # Valid
    else
        return 1  # Invalid
    fi
}
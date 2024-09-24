#!/bin/bash

# File to store the last used SSH hosts
CONFIG_FILE="$HOME/.sssh_config.json"
# File to store the SSH connection history
HISTORY_FILE="$HOME/.sssh_history.log"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

# Flag to track if --force is provided
force_mode=false

# Loop through all arguments to find --force
for arg in "$@"; do
    if [[ "$arg" == "--force" ]]; then
        force_mode=true
        break
    fi
done

source '_sssh_functions.sh'
source '_sssh_validations.sh'

# Handling arguments
case "$1" in
    latest)
        get_last_ssh
        ;;
    list)
        list_hosts
        ;;
    connect)
        if [ -z "$2" ]; then
            list_hosts
            _warning "Enter the number of the host to connect to:"
            read index
            connect_by_index "$index"
        else
            connect_by_index "$2"
        fi
        ;;
    remove)
        if [ -z "$2" ]; then
            list_hosts
            _warning "Enter the number of the host to remove:"
            read index
            remove_host "$index"
        else
            remove_host "$2"
        fi
        ;;
    history)
        show_history
        ;;
    clear)
        clear_data
        ;;
    *)
        # If no argument is passed, use the last connected host
        if [ -z "$1" ]; then
            last_host=$(get_last_ssh)
            if [ -n "$last_host" ]; then
                _info "Connecting to last host: $last_host"
                create_connection "$last_host"
            else
                _error "No previous host found."
            fi
        else
            last_host="$1"
            if validate_ssh_host "$last_host"; then
                # Save the last connected host
                save_host_to_list "$last_host"            
                create_connection "$last_host"
            else
                _error "Invalid SSH host format. Please use the format username@hostnameOrIPAddress."
                exit 1
            fi
        fi
        ;;
esac

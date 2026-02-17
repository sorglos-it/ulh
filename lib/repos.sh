#!/bin/bash
# repos.sh - Repository Management for Custom Scripts
# Handles cloning, pulling, and merging custom script repositories

# Get correct yq binary for current architecture
_get_yq() {
    if [[ -z "$_YQ_CACHE" ]]; then
        local arch=$(uname -m)
        case "$arch" in
            x86_64) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-amd64" ;;
            aarch64) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-arm64" ;;
            armv7l) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-arm" ;;
            i686) _YQ_CACHE="${LIAUH_DIR}/lib/yq/yq-386" ;;
            *) _YQ_CACHE="yq" ;;  # Fallback to PATH
        esac
        [[ -x "$_YQ_CACHE" ]] || chmod +x "$_YQ_CACHE" 2>/dev/null
    fi
    echo "$_YQ_CACHE"
}

# Helper: execute yq with proper binary
_yq_eval() {
    local yq=$(_get_yq)
    "$yq" eval "$@"
}

# Initialize repository system
repo_init() {
    local repo_config="${1:-.}/custom/repo.yaml"
    
    if [[ ! -f "$repo_config" ]]; then
        return 0
    fi
    
    msg_info "Initializing custom repositories..."
    repo_sync_all "$repo_config"
}

# Sync all repositories (clone if missing, pull if exists)
repo_sync_all() {
    local repo_config="$1"
    local auto_update_on_start
    
    auto_update_on_start=$(_yq_eval ".update_settings.auto_update_on_start // true" "$repo_config" 2>/dev/null)
    
    if [[ "$auto_update_on_start" != "true" ]]; then
        msg_info "Custom repo auto-update disabled"
        return 0
    fi
    
    local repo_names
    repo_names=$(_yq_eval ".repositories | keys | .[]" "$repo_config" 2>/dev/null)
    
    for repo_name in $repo_names; do
        repo_sync_one "$repo_config" "$repo_name"
    done
}

# Sync single repository
repo_sync_one() {
    local repo_config="$1"
    local repo_name="$2"
    
    local enabled url path auth_method auto_update
    
    enabled=$(_yq_eval ".repositories.$repo_name.enabled // false" "$repo_config" 2>/dev/null)
    
    if [[ "$enabled" != "true" ]]; then
        return 0
    fi
    
    auto_update=$(_yq_eval ".repositories.$repo_name.auto_update // true" "$repo_config" 2>/dev/null)
    url=$(_yq_eval ".repositories.$repo_name.url" "$repo_config" 2>/dev/null)
    path=$(_yq_eval ".repositories.$repo_name.path" "$repo_config" 2>/dev/null)
    auth_method=$(_yq_eval ".repositories.$repo_name.auth_method // none" "$repo_config" 2>/dev/null)
    
    if [[ -z "$url" || -z "$path" ]]; then
        msg_warn "Repository '$repo_name' missing url or path, skipping"
        return 1
    fi
    
    # Resolve path - automatically prefix with custom/
    if [[ "$path" != /* ]]; then
        path="${LIAUH_DIR}/custom/${path}"
    fi
    
    if [[ -d "$path/.git" ]]; then
        # Repository exists, pull if auto_update is true
        if [[ "$auto_update" == "true" ]]; then
            repo_pull "$repo_name" "$url" "$path" "$auth_method" "$repo_config"
        else
            msg_info "Skipping auto-update for '$repo_name' (auto_update: false)"
        fi
    else
        # Repository doesn't exist, clone it
        repo_clone "$repo_name" "$url" "$path" "$auth_method" "$repo_config"
    fi
}

# Clone repository with authentication
repo_clone() {
    local repo_name="$1"
    local url="$2"
    local path="$3"
    local auth_method="$4"
    local repo_config="$5"
    
    local auth_url retry_count retry_delay max_retries
    
    auth_url=$(repo_auth_url "$url" "$auth_method" "$repo_config" "$repo_name")
    max_retries=$(_yq_eval ".update_settings.retry_on_failure // 3" "$repo_config" 2>/dev/null)
    retry_delay=$(_yq_eval ".update_settings.retry_delay_seconds // 5" "$repo_config" 2>/dev/null)
    
    msg_info "Cloning '$repo_name' to $path..."
    
    # Create parent directory if needed
    mkdir -p "$(dirname "$path")" || return 1
    
    # Setup SSH auth if needed
    if [[ "$auth_method" == "ssh" ]]; then
        local ssh_key
        ssh_key=$(_yq_eval ".repositories.$repo_name.ssh_key" "$repo_config" 2>/dev/null)
        ssh_key=$(repo_resolve_ssh_key "$ssh_key")
        if [[ -n "$ssh_key" && -f "$ssh_key" ]]; then
            export GIT_SSH_COMMAND="ssh -i $ssh_key"
        fi
    fi
    
    retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        if git clone "$auth_url" "$path" 2>/dev/null; then
            msg_info "Successfully cloned '$repo_name'"
            unset GIT_SSH_COMMAND
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            msg_warn "Clone failed for '$repo_name', retrying... (attempt $retry_count/$max_retries)"
            sleep "$retry_delay"
        fi
    done
    
    msg_err "Failed to clone '$repo_name' after $max_retries attempts"
    unset GIT_SSH_COMMAND
    return 1
}

# Pull repository updates with authentication
repo_pull() {
    local repo_name="$1"
    local url="$2"
    local path="$3"
    local auth_method="$4"
    local repo_config="$5"
    
    local retry_count retry_delay max_retries
    
    max_retries=$(_yq_eval ".update_settings.retry_on_failure // 3" "$repo_config" 2>/dev/null)
    retry_delay=$(_yq_eval ".update_settings.retry_delay_seconds // 5" "$repo_config" 2>/dev/null)
    
    msg_info "Updating '$repo_name'..."
    
    retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        cd "$path" || return 1
        
        # Setup auth for SSH if needed
        if [[ "$auth_method" == "ssh" ]]; then
            local ssh_key
            ssh_key=$(_yq_eval ".repositories.$repo_name.ssh_key" "$repo_config" 2>/dev/null)
            ssh_key=$(repo_resolve_ssh_key "$ssh_key")
            if [[ -n "$ssh_key" && -f "$ssh_key" ]]; then
                export GIT_SSH_COMMAND="ssh -i $ssh_key"
            fi
        fi
        
        if git pull origin main 2>/dev/null || git pull origin master 2>/dev/null; then
            msg_info "Successfully updated '$repo_name'"
            unset GIT_SSH_COMMAND
            cd - > /dev/null
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            msg_warn "Pull failed for '$repo_name', retrying... (attempt $retry_count/$max_retries)"
            sleep "$retry_delay"
        fi
        cd - > /dev/null
    done
    
    msg_err "Failed to update '$repo_name' after $max_retries attempts"
    unset GIT_SSH_COMMAND
    return 1
}

# Build authenticated git URL
repo_auth_url() {
    local url="$1"
    local auth_method="$2"
    local repo_config="$3"
    local repo_name="$4"
    
    case "$auth_method" in
        none)
            echo "$url"
            ;;
        https_token)
            local token
            token=$(_yq_eval ".repositories.$repo_name.token" "$repo_config" 2>/dev/null)
            token=$(repo_expand_var "$token")
            
            if [[ -z "$token" || "$token" == "null" ]]; then
                msg_err "Token not set for '$repo_name'"
                echo "$url"
            else
                # Convert https://github.com/org/repo.git -> https://token@github.com/org/repo.git
                url="${url#https://}"
                echo "https://${token}@${url}"
            fi
            ;;
        https_basic)
            local username password
            username=$(_yq_eval ".repositories.$repo_name.username" "$repo_config" 2>/dev/null)
            password=$(_yq_eval ".repositories.$repo_name.password" "$repo_config" 2>/dev/null)
            username=$(repo_expand_var "$username")
            password=$(repo_expand_var "$password")
            
            if [[ -z "$username" || "$username" == "null" ]]; then
                msg_err "Username not set for '$repo_name'"
                echo "$url"
            else
                # Convert https://github.com/org/repo.git -> https://user:pass@github.com/org/repo.git
                url="${url#https://}"
                echo "https://${username}:${password}@${url}"
            fi
            ;;
        ssh)
            echo "$url"
            ;;
        *)
            msg_err "Unknown auth_method: $auth_method"
            echo "$url"
            ;;
    esac
}

# Expand environment variables in configuration values
repo_expand_var() {
    local value="$1"
    
    # Replace ${VAR_NAME} with environment variable value
    while [[ "$value" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name}"
        value="${value/\$\{$var_name\}/$var_value}"
    done
    
    echo "$value"
}

# Resolve SSH key path (can be filename in custom/keys/ or full path)
repo_resolve_ssh_key() {
    local ssh_key="$1"
    
    [[ -z "$ssh_key" || "$ssh_key" == "null" ]] && return 1
    
    # Expand environment variables first
    ssh_key=$(repo_expand_var "$ssh_key")
    
    # Absolute path or ~ path - use as-is
    if [[ "$ssh_key" == /* || "$ssh_key" == ~* ]]; then
        echo "$ssh_key"
        return 0
    fi
    
    # Relative filename - try custom/keys/ first, then ~/.ssh/
    local key_in_custom="${LIAUH_DIR}/custom/keys/${ssh_key}"
    if [[ -f "$key_in_custom" ]]; then
        echo "$key_in_custom"
        return 0
    fi
    
    # Fallback to ~/.ssh/
    local key_in_home="${HOME}/.ssh/${ssh_key}"
    if [[ -f "$key_in_home" ]]; then
        echo "$key_in_home"
        return 0
    fi
    
    # Last resort - return as-is (will fail later if not found)
    echo "$ssh_key"
}

# Get list of enabled repositories (for menu)
repo_list_enabled() {
    local repo_config="${1:-.}/custom/repo.yaml"
    
    if [[ ! -f "$repo_config" ]]; then
        return 1
    fi
    
    local repo_names
    repo_names=$(_yq_eval ".repositories | keys | .[]" "$repo_config" 2>/dev/null)
    
    while IFS= read -r repo_name; do
        [[ -z "$repo_name" ]] && continue
        local enabled
        enabled=$(_yq_eval ".repositories.$repo_name.enabled // false" "$repo_config" 2>/dev/null)
        if [[ "$enabled" == "true" ]]; then
            echo "$repo_name"
        fi
    done <<< "$repo_names"
}

# Get repository display name
repo_get_name() {
    local repo_config="${1:-.}/custom/repo.yaml"
    local repo_id="$2"
    
    _yq_eval ".repositories.$repo_id.name" "$repo_config" 2>/dev/null
}

# Get repository path
repo_get_path() {
    local repo_config="${1:-.}/custom/repo.yaml"
    local repo_id="$2"
    
    local path
    path=$(_yq_eval ".repositories.$repo_id.path" "$repo_config" 2>/dev/null)
    
    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        echo "${LIAUH_DIR}/custom/${path}"
    fi
}

# Check if custom repo has any enabled scripts
repo_has_scripts() {
    local repo_path="$1"
    
    if [[ ! -f "$repo_path/custom.yaml" ]]; then
        return 1
    fi
    
    # Try to get script count
    local count
    count=$(_yq_eval ".scripts | length" "$repo_path/custom.yaml" 2>/dev/null)
    [[ -n "$count" && "$count" != "null" && "$count" -gt 0 ]]
}

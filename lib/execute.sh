#!/bin/bash
# LIAUH - Script Execution Engine (prompts, validation, execution)

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

# Prompt a single question with type validation
# Returns answer on stdout
_prompt_by_type() {
    local question="$1" type="$2" default="$3" answer

    while true; do
        if [[ -n "$default" ]]; then
            printf "  %b%s%b [%b%s%b]: " "$C_CYAN" "$question" "$C_RESET" "$C_GREEN" "$default" "$C_RESET" >&2
        else
            printf "  %b%s%b: " "$C_CYAN" "$question" "$C_RESET" >&2
        fi
        read -r answer
        [[ -z "$answer" ]] && answer="$default"

        case "$type" in
            yes/no|yesno)
                if [[ "${answer,,}" =~ ^(y|yes|n|no)$ ]]; then
                    [[ "${answer,,}" =~ ^(y|yes)$ ]] && answer="yes" || answer="no"
                    break
                fi
                printf "  %b%s%b\n" "$C_RED" "Please answer yes/no" "$C_RESET" >&2
                ;;
            number)
                if [[ "$answer" =~ ^[0-9]+$ ]]; then break; fi
                printf "  %b%s%b\n" "$C_RED" "Please enter a valid number" "$C_RESET" >&2
                ;;
            *)
                if [[ -n "$answer" ]]; then break; fi
                printf "  %b%s%b\n" "$C_RED" "Cannot be empty" "$C_RESET" >&2
                ;;
        esac
    done
    echo "$answer"
}

# Collect prompt answers from YAML config, then run the script
execute_action() {
    local script="$1" action_index="$2"
    local script_path=$(yaml_script_path "$script")
    local needs_sudo=$(yaml_info "$script" "needs_sudo")
    local parameter=$(yaml_action_param "$script" "$action_index")
    local aname=$(yaml_action_name "$script" "$action_index")

    [[ ! -f "$script_path" ]] && { menu_error "Script not found: $script_path"; return 1; }
    [[ ! -x "$script_path" ]] && chmod +x "$script_path" 2>/dev/null

    # Collect prompt answers
    local prompt_count=$(yaml_prompt_count "$script" "$action_index")
    [[ -z "$prompt_count" || "$prompt_count" == "null" ]] && prompt_count=0
    local -a answers=()
    local -a varnames=()

    if (( prompt_count > 0 )); then
        echo ""
        separator
        echo "  Configuration for: ${aname}"
        separator
        echo ""

        for ((i=0; i<prompt_count; i++)); do
            local question=$(yaml_prompt_field "$script" "$action_index" "$i" "question")
            local ptype=$(yaml_prompt_field "$script" "$action_index" "$i" "type")
            local default=$(yaml_prompt_field "$script" "$action_index" "$i" "default")
            local varname=$(yaml_prompt_var "$script" "$action_index" "$i")

            local answer=$(_prompt_by_type "$question" "$ptype" "$default")

            if [[ -n "$varname" && "$varname" != "null" ]]; then
                varnames+=("$varname")
            fi
            answers+=("$answer")
        done
        echo ""
    fi

    # Confirm before execution
    menu_confirm "Execute '${aname}' now?" || {
        return 1
    }

    # Execute
    echo ""
    separator
    echo "  Executing: ${script} → ${aname}"
    separator
    echo ""

    # Build comma-separated parameter string
    # Format: action,DOMAIN=value,SSL=value,...
    local param_string="$parameter"
    
    for ((i=0; i<${#varnames[@]}; i++)); do
        param_string+=",${varnames[$i]}=${answers[$i]}"
    done

    local exit_code=0
    if [[ "$needs_sudo" == "true" ]]; then
        # Execute with sudo - password cached by sudo itself
        # Script receives full parameter string and must parse it
        sudo bash "$script_path" "$param_string" || exit_code=$?
    else
        bash "$script_path" "$param_string" || exit_code=$?
    fi

    echo ""
    separator
    (( exit_code == 0 )) && echo "  ✅ Completed successfully" || echo "  ❌ Failed (exit code: $exit_code)"
    echo ""
    read -rp "  Press Enter..."
    return $exit_code
}

# Execute action from custom repository
# repo_name: repository ID, repo_path: path to cloned repo, script_name: script name, action_index: which action
execute_custom_repo_action() {
    local repo_name="$1"
    local repo_path="$2"
    local script_name="$3"
    local action_index="$4"
    
    local custom_yaml="$repo_path/custom.yaml"
    
    [[ ! -f "$custom_yaml" ]] && { menu_error "custom.yaml not found in $repo_path"; return 1; }
    
    # Get script path from repo
    local script_file=$(_yq_eval ".scripts.$script_name.path" "$custom_yaml" 2>/dev/null)
    local script_path="$repo_path/$script_file"
    
    [[ ! -f "$script_path" ]] && { menu_error "Script not found: $script_path"; return 1; }
    [[ ! -x "$script_path" ]] && chmod +x "$script_path" 2>/dev/null
    
    # Get action details
    local aname=$(_yq_eval ".scripts.$script_name.actions[$action_index].name" "$custom_yaml" 2>/dev/null)
    local parameter=$(_yq_eval ".scripts.$script_name.actions[$action_index].parameter" "$custom_yaml" 2>/dev/null)
    local needs_sudo=$(_yq_eval ".scripts.$script_name.needs_sudo // false" "$custom_yaml" 2>/dev/null)
    local prompt_count=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts | length" "$custom_yaml" 2>/dev/null)
    [[ -z "$prompt_count" || "$prompt_count" == "null" ]] && prompt_count=0
    
    local -a answers=()
    local -a varnames=()
    
    if (( prompt_count > 0 )); then
        echo ""
        separator
        echo "  Configuration for: ${aname}"
        separator
        echo ""
        
        for ((i=0; i<prompt_count; i++)); do
            local question=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].question" "$custom_yaml" 2>/dev/null)
            local ptype=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].type" "$custom_yaml" 2>/dev/null)
            local default=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].default" "$custom_yaml" 2>/dev/null)
            local varname=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].variable" "$custom_yaml" 2>/dev/null)
            
            local answer=$(_prompt_by_type "$question" "$ptype" "$default")
            
            if [[ -n "$varname" && "$varname" != "null" ]]; then
                varnames+=("$varname")
            fi
            answers+=("$answer")
        done
        echo ""
    fi
    
    # Confirm before execution
    menu_confirm "Execute '${aname}' now?" || {
        return 1
    }
    
    # Execute
    echo ""
    separator
    echo "  Executing: ${script_name} → ${aname}"
    separator
    echo ""
    
    # Build comma-separated parameter string
    local param_string="$parameter"
    
    for ((i=0; i<${#varnames[@]}; i++)); do
        param_string+=",${varnames[$i]}=${answers[$i]}"
    done
    
    local exit_code=0
    if [[ "$needs_sudo" == "true" ]]; then
        sudo bash "$script_path" "$param_string" || exit_code=$?
    else
        bash "$script_path" "$param_string" || exit_code=$?
    fi
    
    echo ""
    separator
    (( exit_code == 0 )) && echo "  ✅ Completed successfully" || echo "  ❌ Failed (exit code: $exit_code)"
    echo ""
    read -rp "  Press Enter..."
    return $exit_code
}

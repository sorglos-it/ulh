#!/bin/bash
# ulh - Script Execution Engine (prompts, validation, execution)

# Load colors
source "$(dirname "$0")/colors.sh"

# Get correct yq binary for current architecture
_get_yq() {
    if [[ -z "$_YQ_CACHE" ]]; then
        local arch=$(uname -m)
        case "$arch" in
            x86_64) _YQ_CACHE="${ulh_DIR}/lib/yq/yq-amd64" ;;
            aarch64) _YQ_CACHE="${ulh_DIR}/lib/yq/yq-arm64" ;;
            armv7l) _YQ_CACHE="${ulh_DIR}/lib/yq/yq-arm" ;;
            i686) _YQ_CACHE="${ulh_DIR}/lib/yq/yq-386" ;;
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

# Load and cache answer.yaml file
_load_answers() {
    if [[ -z "$_ANSWERS_CACHE" ]]; then
        local answers_file="${ulh_DIR}/custom/answer.yaml"
        if [[ -f "$answers_file" ]]; then
            # Validate YAML syntax
            if _yq_eval 'keys' "$answers_file" &>/dev/null; then
                _ANSWERS_CACHE="$answers_file"
            else
                _ANSWERS_CACHE="invalid"
                return 1
            fi
        else
            _ANSWERS_CACHE="none"
        fi
    fi
    [[ "$_ANSWERS_CACHE" != "none" && "$_ANSWERS_CACHE" != "invalid" ]]
}

# Get per-script autoscript flag from answer.yaml (presence check)
# Args: script_name
# Returns: 0 (autoscript field present) or 1 (autoscript field not present)
# Note: Checks for field PRESENCE, not value. autoscript: (no value) = enabled
_get_script_autoscript() {
    local script_name="$1"
    
    if _load_answers; then
        # Use 'has' to check if field exists (works with null values)
        # If the field exists (presence check), return 0; otherwise return 1
        local has_autoscript=$(_yq_eval ".scripts.${script_name} | has(\"autoscript\")" "$_ANSWERS_CACHE" 2>/dev/null)
        [[ "$has_autoscript" == "true" ]] && return 0 || return 1
    fi
    return 1  # Default to interactive mode (autoscript field not present)
}

# Check if all required answers are present for a script
# Args: script_name, prompt_count
# Returns: 0 if all answers present, 1 if any missing
_has_all_answers() {
    local script_name="$1" prompt_count="$2"
    
    for ((i=0; i<prompt_count; i++)); do
        local answer=$(_get_answer_default "$script_name" "$i")
        [[ -z "$answer" ]] && return 1  # Missing answer found
    done
    return 0  # All answers present
}

# Get a default answer from answer.yaml if it exists
# Args: script_name, prompt_index (0-based)
# Returns: answer on stdout, or empty if not found
_get_answer_default() {
    local script_name="$1" prompt_index="$2"
    
    if _load_answers; then
        local answer=$(_yq_eval ".scripts.${script_name}.config[${prompt_index}].default // \"\"" "$_ANSWERS_CACHE" 2>/dev/null)
        echo "$answer"
    fi
}

# Prompt a single question with type validation
# Args: question, type, default, autoscript_mode (optional)
# autoscript_mode: if true, use default directly without prompting
# Returns answer on stdout
_prompt_by_type() {
    local question="$1" type="$2" default="$3" autoscript_mode="${4:-false}" answer

    # If autoscript mode and default present, use it directly
    if [[ "$autoscript_mode" == "true" && -n "$default" ]]; then
        echo "$default"
        return 0
    fi

    # Interactive mode: show prompt and allow user override
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

    # Determine autoscript mode for this script
    local autoscript_mode="false"
    if _get_script_autoscript "$script"; then
        autoscript_mode="true"
    fi

    # Collect prompt answers
    local prompt_count=$(yaml_prompt_count "$script" "$action_index")
    [[ -z "$prompt_count" || "$prompt_count" == "null" ]] && prompt_count=0
    local -a answers=()
    local -a varnames=()

    if (( prompt_count > 0 )); then
        # Check if we can use autoscript mode (all answers must be present)
        if [[ "$autoscript_mode" == "true" ]]; then
            if ! _has_all_answers "$script" "$prompt_count"; then
                # Graceful fallback: missing answers, show interactive prompts
                msg_warn "Autoscript mode enabled but missing answers, falling back to interactive mode"
                autoscript_mode="false"
            fi
        fi

        # Show header only if not pure autoscript mode
        if [[ "$autoscript_mode" == "false" ]]; then
            echo ""
            separator
            echo "  Configuration for: ${aname}"
            separator
            echo ""
        fi

        for ((i=0; i<prompt_count; i++)); do
            local question=$(yaml_prompt_field "$script" "$action_index" "$i" "question")
            local ptype=$(yaml_prompt_field "$script" "$action_index" "$i" "type")
            local config_default=$(yaml_prompt_field "$script" "$action_index" "$i" "default")
            local varname=$(yaml_prompt_var "$script" "$action_index" "$i")

            # Merge defaults: prefer answer.yaml, fall back to config.yaml
            local answer_yaml_default=$(_get_answer_default "$script" "$i")
            local final_default="${answer_yaml_default:-$config_default}"
            
            # Prompt user or use default directly (based on autoscript mode)
            local answer=$(_prompt_by_type "$question" "$ptype" "$final_default" "$autoscript_mode")

            if [[ -n "$varname" && "$varname" != "null" ]]; then
                varnames+=("$varname")
            fi
            answers+=("$answer")
        done
        
        if [[ "$autoscript_mode" == "false" ]]; then
            echo ""
        fi
    fi

    # Skip confirmation in pure autoscript mode
    if [[ "$autoscript_mode" != "true" ]]; then
        # Confirm before execution
        menu_confirm "Execute '${aname}' now?" || {
            return 1
        }
    else
        msg_info "Autoscript mode: executing '${aname}' automatically"
    fi

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
    
    # Skip pause in pure autoscript mode
    if [[ "$autoscript_mode" != "true" ]]; then
        read -rp "  Press Enter..."
    fi
    
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
    
    # Determine autoscript mode for this script
    local autoscript_mode="false"
    if _get_script_autoscript "$script_name"; then
        autoscript_mode="true"
    fi
    
    local -a answers=()
    local -a varnames=()
    
    if (( prompt_count > 0 )); then
        # Check if we can use autoscript mode (all answers must be present)
        if [[ "$autoscript_mode" == "true" ]]; then
            if ! _has_all_answers "$script_name" "$prompt_count"; then
                # Graceful fallback: missing answers, show interactive prompts
                msg_warn "Autoscript mode enabled but missing answers, falling back to interactive mode"
                autoscript_mode="false"
            fi
        fi

        # Show header only if not pure autoscript mode
        if [[ "$autoscript_mode" == "false" ]]; then
            echo ""
            separator
            echo "  Configuration for: ${aname}"
            separator
            echo ""
        fi
        
        for ((i=0; i<prompt_count; i++)); do
            local question=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].question" "$custom_yaml" 2>/dev/null)
            local ptype=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].type" "$custom_yaml" 2>/dev/null)
            local config_default=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].default" "$custom_yaml" 2>/dev/null)
            local varname=$(_yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].variable" "$custom_yaml" 2>/dev/null)
            
            # Merge defaults: prefer answer.yaml, fall back to config.yaml
            local answer_yaml_default=$(_get_answer_default "$script_name" "$i")
            local final_default="${answer_yaml_default:-$config_default}"
            
            # Prompt user or use default directly (based on autoscript mode)
            local answer=$(_prompt_by_type "$question" "$ptype" "$final_default" "$autoscript_mode")
            
            if [[ -n "$varname" && "$varname" != "null" ]]; then
                varnames+=("$varname")
            fi
            answers+=("$answer")
        done
        
        if [[ "$autoscript_mode" == "false" ]]; then
            echo ""
        fi
    fi
    
    # Skip confirmation in pure autoscript mode
    if [[ "$autoscript_mode" != "true" ]]; then
        # Confirm before execution
        menu_confirm "Execute '${aname}' now?" || {
            return 1
        }
    else
        msg_info "Autoscript mode: executing '${aname}' automatically"
    fi
    
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
        # Execute with sudo - password cached by sudo itself
        sudo bash "$script_path" "$param_string" || exit_code=$?
    else
        bash "$script_path" "$param_string" || exit_code=$?
    fi
    
    echo ""
    separator
    (( exit_code == 0 )) && echo "  ✅ Completed successfully" || echo "  ❌ Failed (exit code: $exit_code)"
    echo ""
    
    # Skip pause in pure autoscript mode
    if [[ "$autoscript_mode" != "true" ]]; then
        read -rp "  Press Enter..."
    fi
    
    return $exit_code
}

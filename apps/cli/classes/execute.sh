#!/bin/bash
# ulh - Script Execution Engine (prompts, validation, execution)

# Load colors from centralized library
source "${BASH_SOURCE%/*}/colors.sh"

# yq: get_yq / yq_eval come from yaml.sh

# Load and cache answer.yaml file
load_answers() {
    if [[ -z "$_ANSWERS_CACHE" ]]; then
        # Try ulh_DIR first, then derive from BASH_SOURCE if not available
        local base_dir="${ulh_DIR}"
        [[ -z "$base_dir" ]] && base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        local answers_file="${base_dir}/config/answer.yaml"
        
        if [[ -f "$answers_file" ]]; then
            # Validate YAML syntax
            if yq_eval 'keys' "$answers_file" &>/dev/null; then
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

# Get autoscript flag for an action from answer.yaml
# Args: script_name, action_name
# Returns: 0 (autoscript enabled) or 1 (autoscript disabled/not present)
# Note: Checks if autoscript field is present and truthy
get_action_autoscript() {
    local script_name="$1"
    local action_name="$2"
    
    if load_answers; then
        # Check if autoscript field exists and is truthy
        local autoscript_value=$(yq_eval ".scripts.${script_name}.${action_name}.autoscript // \"false\"" "$_ANSWERS_CACHE" 2>/dev/null)
        
        # Treat as enabled if value is: true, yes, 1, or any non-empty/non-null value
        case "$autoscript_value" in
            true|yes|1) return 0 ;;  # Autoscript enabled
            *) return 1 ;;           # Autoscript disabled
        esac
    fi
    return 1  # Default to interactive mode
}

# Check if all required answers are present for a script action
# Args: script_name, action_name, prompt_count
# Returns: 0 if all answers present, 1 if any missing
has_all_answers() {
    local script_name="$1" action_name="$2" prompt_count="$3"
    
    for ((i=0; i<prompt_count; i++)); do
        local answer=$(get_answer_default "$script_name" "$action_name" "$i")
        [[ -z "$answer" ]] && return 1  # Missing answer found
    done
    return 0  # All answers present
}

# Get a default answer from answer.yaml if it exists
# Args: script_name, action_name, prompt_index (0-based)
# Returns: answer on stdout, or empty if not found
get_answer_default() {
    local script_name="$1" action_name="$2" prompt_index="$3"
    
    if load_answers; then
        # Try new format first: .scripts.${script}.${action}.answers[index]
        local answer=$(yq_eval ".scripts.${script_name}.${action_name}.answers[${prompt_index}].default // \"\"" "$_ANSWERS_CACHE" 2>/dev/null)
        
        # Fallback: old format (direct array) .scripts.${script}.${action}[index]
        if [[ -z "$answer" || "$answer" == "null" ]]; then
            answer=$(yq_eval ".scripts.${script_name}.${action_name}[${prompt_index}].default // \"\"" "$_ANSWERS_CACHE" 2>/dev/null)
        fi
        
        # Only echo if not null/empty
        [[ "$answer" != "null" ]] && echo "$answer"
    fi
}

# Prompt a single question with type validation
# Args: question, type, default, autoscript_mode (optional)
# autoscript_mode: if true, use default directly without prompting
# Returns answer on stdout
prompt_by_type() {
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
                # Text type: accept answer as-is (empty is allowed if default was empty)
                break
                ;;
        esac
    done
    echo "$answer"
}

# Collect prompt answers from YAML config, then run the script
execute_action() {
    local script="$1" action_index="$2"
    local script_path=$(yaml_script_path "$script")
    # Check if sudo field exists (presence-based) using has()
    local base_dir="${ulh_DIR}"
    [[ -z "$base_dir" ]] && base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local needs_sudo=$(yq_eval ".scripts.${script} | has(\"sudo\")" "${base_dir}/assets/catalog.yaml" 2>/dev/null)
    [[ "$needs_sudo" == "true" ]] && needs_sudo="true" || needs_sudo="false"
    local parameter=$(yaml_action_param "$script" "$action_index")
    local aname=$(yaml_action_name "$script" "$action_index")

    [[ ! -f "$script_path" ]] && { menu_error "Script not found: $script_path"; return 1; }

    # Determine autoscript mode for this action (using parameter as action key)
    local autoscript_mode="false"
    if get_action_autoscript "$script" "$parameter"; then
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
            if ! has_all_answers "$script" "$parameter" "$prompt_count"; then
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

            # Merge defaults: prefer answer.yaml, fall back to catalog.yaml
            local answer_yaml_default=$(get_answer_default "$script" "$parameter" "$i")
            local final_default="${answer_yaml_default:-$config_default}"
            
            # Prompt user or use default directly (based on autoscript mode)
            local answer=$(prompt_by_type "$question" "$ptype" "$final_default" "$autoscript_mode")

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
    
    # Custom repos have their own config.yaml (not custom.yaml)
    local custom_yaml="$repo_path/config.yaml"
    
    [[ ! -f "$custom_yaml" ]] && { menu_error "config.yaml not found in $repo_path"; return 1; }
    
    # Get script path from repo
    local script_file=$(yq_eval ".scripts.$script_name.path" "$custom_yaml" 2>/dev/null)
    local script_path="$repo_path/$script_file"
    
    # Fallback: if script not found, try scripts/ subdirectory (like main ulh scripts structure)
    if [[ ! -f "$script_path" ]]; then
        script_path="$repo_path/scripts/$script_file"
    fi
    
    [[ ! -f "$script_path" ]] && { menu_error "Script not found: $repo_path/$script_file or $repo_path/scripts/$script_file"; return 1; }
    
    # Get action details
    local aname=$(yq_eval ".scripts.$script_name.actions[$action_index].name" "$custom_yaml" 2>/dev/null)
    local parameter=$(yq_eval ".scripts.$script_name.actions[$action_index].parameter" "$custom_yaml" 2>/dev/null)
    # Check if sudo field exists (presence-based) using has()
    local needs_sudo=$(yq_eval ".scripts.$script_name | has(\"sudo\")" "$custom_yaml" 2>/dev/null)
    [[ "$needs_sudo" == "true" ]] && needs_sudo="true" || needs_sudo="false"
    local prompt_count=$(yq_eval ".scripts.$script_name.actions[$action_index].prompts | length" "$custom_yaml" 2>/dev/null)
    [[ -z "$prompt_count" || "$prompt_count" == "null" ]] && prompt_count=0
    
    # Determine autoscript mode for this action (using parameter as action key)
    local autoscript_mode="false"
    if get_action_autoscript "$script_name" "$parameter"; then
        autoscript_mode="true"
    fi
    
    local -a answers=()
    local -a varnames=()
    
    if (( prompt_count > 0 )); then
        # Check if we can use autoscript mode (all answers must be present)
        if [[ "$autoscript_mode" == "true" ]]; then
            if ! has_all_answers "$script_name" "$parameter" "$prompt_count"; then
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
            local question=$(yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].question" "$custom_yaml" 2>/dev/null)
            local ptype=$(yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].type" "$custom_yaml" 2>/dev/null)
            local config_default=$(yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].default" "$custom_yaml" 2>/dev/null)
            local varname=$(yq_eval ".scripts.$script_name.actions[$action_index].prompts[$i].variable" "$custom_yaml" 2>/dev/null)
            
            # Merge defaults: prefer answer.yaml, fall back to config.yaml
            local answer_yaml_default=$(get_answer_default "$script_name" "$parameter" "$i")
            local final_default="${answer_yaml_default:-$config_default}"
            
            # Prompt user or use default directly (based on autoscript mode)
            local answer=$(prompt_by_type "$question" "$ptype" "$final_default" "$autoscript_mode")
            
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

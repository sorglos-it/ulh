#!/bin/bash

# ULH Colors and Graphics Library
# Central place for all color definitions and visual elements
# Source this file: source "$(dirname "$0")/colors.sh"

# ============================================================
# BASIC ANSI COLOR CODES
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'  # No Color (reset)

# ============================================================
# EXTENDED ANSI COLOR CODES (for compatibility with existing code)
# ============================================================

export COLOR_RESET=$'\033[0m'
export COLOR_BOLD=$'\033[1m'
export COLOR_DIM=$'\033[2m'
export COLOR_UNDERLINE=$'\033[4m'

export COLOR_BLACK=$'\033[0;30m'
export COLOR_RED=$'\033[0;31m'
export COLOR_GREEN=$'\033[0;32m'
export COLOR_YELLOW=$'\033[0;33m'
export COLOR_BLUE=$'\033[0;34m'
export COLOR_MAGENTA=$'\033[0;35m'
export COLOR_CYAN=$'\033[0;36m'
export COLOR_WHITE=$'\033[0;37m'

export COLOR_BOLD_RED=$'\033[1;31m'
export COLOR_BOLD_GREEN=$'\033[1;32m'
export COLOR_BOLD_YELLOW=$'\033[1;33m'
export COLOR_BOLD_BLUE=$'\033[1;34m'
export COLOR_BOLD_CYAN=$'\033[1;36m'
export COLOR_BOLD_WHITE=$'\033[1;37m'

export COLOR_BG_RED=$'\033[41m'
export COLOR_BG_GREEN=$'\033[42m'
export COLOR_BG_YELLOW=$'\033[43m'

# Shorthand (used in core.sh, menu.sh)
C_RESET="$COLOR_RESET"
C_BOLD="$COLOR_BOLD"
C_BOLD_CYAN="$COLOR_BOLD_CYAN"
C_BOLD_WHITE="$COLOR_BOLD_WHITE"
C_RED="$COLOR_RED"
C_GREEN="$COLOR_GREEN"
C_YELLOW="$COLOR_YELLOW"
C_BLUE="$COLOR_BLUE"
C_CYAN="$COLOR_CYAN"

# ============================================================
# GRAPHIC SYMBOLS
# ============================================================

SYMBOL_CHECK="✓"
SYMBOL_ERROR="✗"
SYMBOL_WARN="⚠"
SYMBOL_INFO="ℹ"
SYMBOL_ARROW="▶"
SYMBOL_BULLET="•"
SYMBOL_DIVIDER="─"
SYMBOL_CORNER_TL="┌"
SYMBOL_CORNER_TR="┐"
SYMBOL_CORNER_BL="└"
SYMBOL_CORNER_BR="┘"
SYMBOL_VERT="│"
SYMBOL_HORIZ="─"

# ============================================================
# COMPOSITE SYMBOLS (for logging)
# ============================================================

PREFIX_OK="${GREEN}${SYMBOL_CHECK}${NC}"
PREFIX_ERROR="${RED}${SYMBOL_ERROR}${NC}"
PREFIX_WARN="${YELLOW}${SYMBOL_WARN}${NC}"
PREFIX_INFO="${BLUE}${SYMBOL_INFO}${NC}"
PREFIX_SECTION="${BLUE}${SYMBOL_ARROW}${NC}"

# ============================================================
# SEPARATOR FUNCTIONS
# ============================================================

# 80-char separator with =
separator() {
    printf '%s\n' "$(printf '=%.0s' {1..80})"
}

# 78-char separator with - (from core.sh)
separator_thin() {
    printf "%78s\n" | tr ' ' '-'
}

# 80-char separator with ─ (from menu.sh)
separator_dots() {
    echo "──────────────────────────────────────────────────────────────────────────────"
}

# ============================================================
# TEXT FORMATTING
# ============================================================

bold() {
    echo -e "\033[1m$1\033[0m"
}

underline() {
    echo -e "\033[4m$1\033[0m"
}

# ============================================================
# EXPORT FLAG
# ============================================================

export COLORS_LOADED=1

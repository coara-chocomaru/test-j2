#!/bin/bash

set -e

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

SCRIPT_NAME="sysnc"
SCRIPT_URL="https://github.com/coara-chocomaru/test-j2/raw/refs/heads/main/sysnc"
RISH_NAME="rish"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RISH_SOURCE="${SCRIPT_DIR}/${RISH_NAME}"

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    cat <<EOF
sysnc installer

Usage: install.sh [OPTIONS]

Options:
  -u, --uninstall   Remove sysnc and rish and exit
  -h, --help        Show this help message

This script must be run inside Termux on Android.
rish must be present in the same directory as this installer.
EOF
}

require_termux() {
    if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
        print_error "This script is designed for Termux."
        print_error "The PREFIX environment variable is not set or does not point to a directory."
        print_error "Please run this script inside the Termux app."
        exit 1
    fi
    INSTALL_DIR="$PREFIX/bin"
}

install_dependencies() {
    print_status "Checking dependencies..."

    if command -v nc &>/dev/null; then
        print_success "netcat already installed"
        return
    fi

    print_warning "netcat not found. Installing netcat-openbsd..."
    pkg update -y || print_warning "pkg update failed; continuing with cached repo data"
    pkg install -y netcat-openbsd
    print_success "netcat installed"
}

validate_script() {
    local file="$1"
    local first_line
    first_line=$(head -n 1 "$file")
    case "$first_line" in
        '#!/bin/bash'|'#!/usr/bin/env bash')
            return 0
            ;;
        *)
            print_error "Downloaded file does not start with a bash shebang: '$first_line'"
            print_error "Refusing to install a potentially corrupted or malicious file."
            return 1
            ;;
    esac
}

download_script() {
    local dest="$1"
    print_status "Downloading sysnc from $SCRIPT_URL ..."

    if command -v curl &>/dev/null; then
        curl -fsSL "$SCRIPT_URL" -o "$dest" \
            || { print_error "curl failed to download sysnc"; return 1; }
    elif command -v wget &>/dev/null; then
        wget -qO "$dest" "$SCRIPT_URL" \
            || { print_error "wget failed to download sysnc"; return 1; }
    else
        print_error "Neither curl nor wget is installed. Install one and retry."
        return 1
    fi
}

install_sysnc() {
    local target="$INSTALL_DIR/$SCRIPT_NAME"

    if [ -e "$target" ]; then
        print_warning "Existing $target will be overwritten"
    fi

    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT

    download_script "$tmp" || exit 1
    validate_script "$tmp" || exit 1

    install -m 755 "$tmp" "$target"
    print_success "sysnc installed to $target"
}

install_rish() {
    local target="$INSTALL_DIR/$RISH_NAME"

    print_status "Installing rish from local file..."

    if [ ! -f "$RISH_SOURCE" ]; then
        print_error "rish not found at: $RISH_SOURCE"
        print_error "Place the rish file in the same directory as this installer and retry."
        exit 1
    fi

    if [ ! -r "$RISH_SOURCE" ]; then
        print_error "rish exists but is not readable: $RISH_SOURCE"
        exit 1
    fi

    if [ -e "$target" ]; then
        print_warning "Existing $target will be overwritten"
    fi

    install -m 755 "$RISH_SOURCE" "$target"
    chmod +x "$target"
    print_success "rish installed to $target"
}

register_rish_command() {
    local target="$INSTALL_DIR/$RISH_NAME"

    print_status "Registering rish as a termux command..."

    case ":$PATH:" in
        *":$INSTALL_DIR:"*)
            ;;
        *)
            export PATH="$INSTALL_DIR:$PATH"
            print_warning "$INSTALL_DIR was not in PATH; added for this session"
            ;;
    esac

    hash -r 2>/dev/null || true

    if [ ! -x "$target" ]; then
        print_error "rish is not executable at $target"
        exit 1
    fi

    local resolved
    resolved=$(command -v "$RISH_NAME" 2>/dev/null || true)

    if [ -z "$resolved" ]; then
        print_error "Failed to register rish command; not resolvable via PATH"
        exit 1
    fi

    if [ "$resolved" != "$target" ]; then
        print_warning "rish resolves to $resolved (not $target)"
        print_warning "Another version may be shadowing the freshly installed one."
    fi

    print_success "rish command registered; you can now run it as: $RISH_NAME"
}

verify_installation() {
    print_status "Verifying installation..."

    if command -v "$SCRIPT_NAME" &>/dev/null; then
        local found
        found=$(command -v "$SCRIPT_NAME")
        if [ "$found" = "$INSTALL_DIR/$SCRIPT_NAME" ]; then
            print_success "$SCRIPT_NAME is on PATH at $found"
        else
            print_warning "$SCRIPT_NAME resolves to $found (not $INSTALL_DIR/$SCRIPT_NAME)"
            print_warning "Another version may be shadowing the freshly installed one."
        fi
    else
        print_error "$SCRIPT_NAME not found on PATH"
        print_error "Try restarting Termux or check that $INSTALL_DIR is on \$PATH."
        exit 1
    fi

    if command -v "$RISH_NAME" &>/dev/null; then
        local found_rish
        found_rish=$(command -v "$RISH_NAME")
        if [ "$found_rish" = "$INSTALL_DIR/$RISH_NAME" ]; then
            print_success "$RISH_NAME is on PATH at $found_rish"
        else
            print_warning "$RISH_NAME resolves to $found_rish (not $INSTALL_DIR/$RISH_NAME)"
            print_warning "Another version may be shadowing the freshly installed one."
        fi
    else
        print_error "$RISH_NAME not found on PATH"
        print_error "Try restarting Termux or check that $INSTALL_DIR is on \$PATH."
        exit 1
    fi
}

uninstall_sysnc() {
    require_termux

    local target_sysnc="$INSTALL_DIR/$SCRIPT_NAME"
    local target_rish="$INSTALL_DIR/$RISH_NAME"

    if [ -e "$target_sysnc" ]; then
        rm -f "$target_sysnc"
        print_success "Removed $target_sysnc"
    else
        print_warning "$target_sysnc not found; nothing to remove"
    fi

    if [ -e "$target_rish" ]; then
        rm -f "$target_rish"
        print_success "Removed $target_rish"
    else
        print_warning "$target_rish not found; nothing to remove"
    fi

    hash -r 2>/dev/null || true
}

main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--uninstall)
            uninstall_sysnc
            exit 0
            ;;
        '') ;;
        *)
            print_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac

    echo "=========================================="
    echo "sysnc Installation Script for Termux"
    echo "=========================================="
    echo ""

    require_termux
    install_dependencies
    install_sysnc
    install_rish
    register_rish_command
    verify_installation

    echo ""
    print_success "Installation complete. Run 'sysnc -h' to get started."
    print_success "rish is also available as the 'rish' command."
}

main "$@"

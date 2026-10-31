#!/usr/bin/env bash
# ==============================================================================
# Rust on Rails CLI Installer
# ==============================================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo ""
echo -e "${BOLD}${CYAN}   ____             __                 ____            ____            _ _     ${NC}"
echo -e "${BOLD}${CYAN}  |  _ \ _   _ ___ / /_     ___  _ __  |  _ \ __ _(_) |___ \     ___  | (_)    ${NC}"
echo -e "${BOLD}${CYAN}  | |_) | | | / __| __|____/ _ \| '_ \ | |_) / _\` | |   __) |   / _ \ | | |    ${NC}"
echo -e "${BOLD}${CYAN}  |  _ <| |_| \__ \ |_|____(_) | | | ||  _ < (_| | |  / __/ _ | (_) || | |    ${NC}"
echo -e "${BOLD}${CYAN}  |_| \_\\__,_|___/\__|     \___/|_| |_||_| \_\__,_|_| |_____(_) \___/ |_|_|    ${NC}"
echo ""
echo -e "   ${BOLD}Installing railst CLI (Rust on Rails Installer & Tooling)${NC}"
echo ""

# 1. Check Ruby requirement
if ! command -v ruby &> /dev/null; then
    echo -e "   ${RED}[ERROR] Ruby is not installed or not in PATH.${NC}"
    echo -e "   Please install Ruby >= 3.2.0 with development headers."
    exit 1
fi

RUBY_VER=$(ruby -e 'puts RUBY_VERSION')
echo -e "   ${GREEN}✓${NC} Detected Ruby: ${BOLD}${RUBY_VER}${NC}"

# 2. Check Cargo / Rust requirement
if ! command -v cargo &> /dev/null; then
    echo -e "   ${YELLOW}[WARN] Cargo / Rust is not detected in PATH.${NC}"
    echo -e "   Rust is required to build the native backend extension."
    echo -e "   Install Rust via: ${BOLD}curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
    echo ""
else
    CARGO_VER=$(cargo --version | head -n 1)
    echo -e "   ${GREEN}✓${NC} Detected Rust: ${BOLD}${CARGO_VER}${NC}"
fi

# 3. Determine installation method
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/packages/railst-cli/railst.gemspec" ]; then
    echo -e "   ${CYAN}•${NC} Building and installing railst gem from local packages/railst-cli..."
    cd "$SCRIPT_DIR/packages/railst-cli"
    rm -f *.gem
    gem build railst.gemspec --silent
    GEM_FILE=$(ls railst-*.gem | head -n 1)
    gem install "$GEM_FILE" --user-install --force --no-document
    rm -f *.gem
    cd "$SCRIPT_DIR"
else
    echo -e "   ${CYAN}•${NC} Installing railst from RubyGems..."
    gem install railst --user-install --no-document
fi

# 4. Ensure user bin path is in PATH
USER_GEM_BIN="$(ruby -r rubygems -e 'puts Gem.user_dir')/bin"
LOCAL_BIN="$HOME/.local/bin"

mkdir -p "$LOCAL_BIN"
if command -v railst &> /dev/null; then
    INSTALLED_PATH="$(which railst)"
    echo -e "   ${GREEN}✓${NC} railst binary active at: ${BOLD}${INSTALLED_PATH}${NC}"
else
    # Link to ~/.local/bin if not immediately found
    if [ -f "$USER_GEM_BIN/railst" ]; then
        ln -sf "$USER_GEM_BIN/railst" "$LOCAL_BIN/railst"
        echo -e "   ${GREEN}✓${NC} Linked railst binary to: ${BOLD}$LOCAL_BIN/railst${NC}"
    fi
fi

echo ""
echo -e "   ${BOLD}${GREEN}Installation Complete!${NC}"
echo ""
echo -e "   ${BOLD}Next Steps:${NC}"
echo -e "   1. Verify environment:   ${YELLOW}railst doctor${NC}"
echo -e "   2. Create new project:   ${YELLOW}railst new my_app${NC}"
echo -e "   3. Run server:           ${YELLOW}cd my_app && railst s${NC}"
echo ""

#!/usr/bin/env bash
# smux — one-command tmux setup
set -euo pipefail

VERSION="1.1.0"
REPO="leegn4a/smux"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SMUX_DIR="$HOME/.smux"
BIN_DIR="$SMUX_DIR/bin"
BACKUP_DIR="$SMUX_DIR/backups"
TMUX_XDG_DIR="$HOME/.config/tmux"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${GREEN}[smux]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[smux]${NC} %s\n" "$*"; }
error() { printf "${RED}[smux]${NC} %s\n" "$*" >&2; exit 1; }

# --- OS / package manager detection ---

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      error "Unsupported OS: $(uname -s)" ;;
  esac
}

detect_pkg_manager() {
  if command -v brew >/dev/null 2>&1; then echo "brew"
  elif command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  elif command -v apk >/dev/null 2>&1; then echo "apk"
  else echo "unknown"
  fi
}

pkg_install() {
  local pkg="$1"
  local mgr
  mgr=$(detect_pkg_manager)
  info "Installing $pkg via $mgr..."
  case "$mgr" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg" ;;
    dnf)    sudo dnf install -y -q "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
    apk)    sudo apk add "$pkg" ;;
    *)      error "No supported package manager found. Install $pkg manually and re-run." ;;
  esac
}

# --- Helpers ---

check_tmux_version() {
  local ver
  ver=$(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
  local major minor
  major=$(echo "$ver" | cut -d. -f1)
  minor=$(echo "$ver" | cut -d. -f2)
  if (( major < 3 || (major == 3 && minor < 2) )); then
    warn "tmux $ver detected. Version 3.2+ recommended for full visual features."
  fi
}

is_wayland_session() {
  [[ -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == "wayland" ]]
}

ensure_clipboard_tool() {
  local os="$1"

  [[ "$os" == "linux" ]] || return

  if is_wayland_session; then
    if ! command -v wl-copy >/dev/null 2>&1; then
      info "Wayland session detected. Installing wl-clipboard..."
      pkg_install wl-clipboard
    fi
    return
  fi

  if ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then
    info "No X11 clipboard tool found. Installing xclip..."
    pkg_install xclip
  fi
}

is_smux_tmux_config() {
  [[ -e "$SMUX_DIR/tmux.conf" && -e "$TMUX_XDG_DIR/tmux.conf" \
    && "$TMUX_XDG_DIR/tmux.conf" -ef "$SMUX_DIR/tmux.conf" ]]
}

backup_existing() {
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP_DIR"

  # Check XDG location
  if [[ -f "$TMUX_XDG_DIR/tmux.conf" ]] && ! is_smux_tmux_config; then
    cp "$TMUX_XDG_DIR/tmux.conf" "$BACKUP_DIR/tmux.conf.$ts"
    info "Backed up ~/.config/tmux/tmux.conf → ~/.smux/backups/tmux.conf.$ts"
  fi

  # Check legacy location
  if [[ -f "$HOME/.tmux.conf" ]]; then
    cp "$HOME/.tmux.conf" "$BACKUP_DIR/tmux.conf.legacy.$ts"
    info "Backed up ~/.tmux.conf → ~/.smux/backups/tmux.conf.legacy.$ts"
  fi
}

download() {
  local url="$1" dest="$2" temp
  temp=$(mktemp "${dest}.tmp.XXXXXX")

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL "$url" -o "$temp"; then
      rm -f "$temp"
      error "Failed to download $url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -qO "$temp" "$url"; then
      rm -f "$temp"
      error "Failed to download $url"
    fi
  else
    rm -f "$temp"
    error "Neither curl nor wget found. Install one and re-run."
  fi

  mv -f "$temp" "$dest"
}

install_runtime_files() {
  info "Downloading tmux.conf..."
  download "$BASE_URL/.tmux.conf" "$SMUX_DIR/tmux.conf"

  info "Downloading tmux-bridge..."
  download "$BASE_URL/scripts/tmux-bridge" "$BIN_DIR/tmux-bridge"
  chmod +x "$BIN_DIR/tmux-bridge"

  info "Downloading clipboard helper..."
  download "$BASE_URL/scripts/smux-clipboard" "$BIN_DIR/smux-clipboard"
  chmod +x "$BIN_DIR/smux-clipboard"

  info "Installing smux CLI..."
  download "$BASE_URL/install.sh" "$BIN_DIR/smux"
  chmod +x "$BIN_DIR/smux"
}

link_tmux_config() {
  mkdir -p "$TMUX_XDG_DIR"
  ln -sf "$SMUX_DIR/tmux.conf" "$TMUX_XDG_DIR/tmux.conf"
}

# --- Commands ---

cmd_install() {
  local os
  os=$(detect_os)
  info "Installing smux ($os)..."

  # 1. Install tmux if missing
  if ! command -v tmux >/dev/null 2>&1; then
    info "tmux not found. Installing..."
    if [[ "$os" == "macos" ]] && ! command -v brew >/dev/null 2>&1; then
      error "Homebrew is required to install tmux on macOS. Install it from https://brew.sh and re-run."
    fi
    pkg_install tmux
  fi
  check_tmux_version

  # 2. Install the clipboard backend for the active graphical session.
  ensure_clipboard_tool "$os"

  # 3. Create directories
  mkdir -p "$SMUX_DIR" "$BIN_DIR" "$BACKUP_DIR"

  # 4. Back up existing config
  backup_existing

  # 5. Download runtime files and activate the tmux config.
  install_runtime_files
  link_tmux_config

  # 6. Reload tmux if running
  if tmux list-sessions &>/dev/null; then
    tmux source-file "$SMUX_DIR/tmux.conf" 2>/dev/null && info "Reloaded tmux config." || true
  fi

  # 7. Done
  echo ""
  printf "${GREEN}${BOLD}smux installed!${NC}\n"
  echo ""
  echo "  Config:       ~/.smux/tmux.conf"
  echo "  tmux-bridge:  ~/.smux/bin/tmux-bridge"
  echo "  smux CLI:     ~/.smux/bin/smux"
  echo ""
  echo "  Run 'smux help' for commands inside tmux."
}

cmd_update() {
  local os
  os=$(detect_os)
  info "Updating smux..."

  mkdir -p "$SMUX_DIR" "$BIN_DIR" "$BACKUP_DIR"
  ensure_clipboard_tool "$os"
  backup_existing

  install_runtime_files
  link_tmux_config

  if tmux list-sessions &>/dev/null; then
    tmux source-file "$SMUX_DIR/tmux.conf" 2>/dev/null && info "Reloaded tmux config." || true
  fi

  printf "${GREEN}${BOLD}smux updated to v${VERSION}!${NC}\n"
}

cmd_uninstall() {
  info "Uninstalling smux..."

  # Remove symlink
  local removed_smux_config=false
  if is_smux_tmux_config; then
    rm "$TMUX_XDG_DIR/tmux.conf"
    removed_smux_config=true
    info "Removed symlink ~/.config/tmux/tmux.conf"
  fi

  # Restore only after removing smux's config. If the user has since replaced
  # the symlink with another config, leave that config untouched.
  local latest_backup
  if $removed_smux_config; then
    # ~/.tmux.conf is left in place, so only restore an XDG config backup.
    latest_backup=$(ls -t "$BACKUP_DIR"/tmux.conf.[0-9]* 2>/dev/null | head -1 || true)
    if [[ -n "$latest_backup" ]]; then
      info "Restoring backup: $latest_backup"
      mkdir -p "$TMUX_XDG_DIR"
      cp "$latest_backup" "$TMUX_XDG_DIR/tmux.conf"
    fi
  fi

  # Remove smux directory
  rm -rf "$SMUX_DIR"
  info "Removed ~/.smux/"

  echo ""
  printf "${GREEN}${BOLD}smux uninstalled.${NC}\n"
  echo ""
  echo "  Note: You may want to remove the PATH line from your shell rc file:"
  echo "    export PATH=\"\$HOME/.smux/bin:\$PATH\""
}

cmd_version() {
  echo "smux $VERSION"
}

cmd_help() {
  cat <<'EOF'
smux — one-command tmux setup

Usage: smux <command>

Commands:
  install     Install smux (tmux config + tmux-bridge)
  update      Update to the latest version
  uninstall   Remove smux and restore previous config
  version     Print version
  help        Show this help

Files:
  ~/.smux/tmux.conf          tmux configuration
  ~/.smux/bin/tmux-bridge    cross-pane communication CLI
  ~/.smux/bin/smux           this CLI
  ~/.smux/backups/           config backups
EOF
}

# --- Main ---

# When invoked as the installed `smux` CLI, default to help (no-op).
# When invoked as install.sh (curl-pipe or `bash install.sh`), default to install.
_smux_script="${BASH_SOURCE[0]:-}"
if [[ -n "$_smux_script" && "$(basename "$_smux_script")" == "smux" ]]; then
  _smux_default="help"
else
  _smux_default="install"
fi

case "${1:-$_smux_default}" in
  install)                    cmd_install ;;
  update)                     cmd_update ;;
  uninstall|remove)           cmd_uninstall ;;
  version|--version|-v|-V)    cmd_version ;;
  help|--help|-h)             cmd_help ;;
  *)                          error "Unknown command: $1. Run 'smux help' for usage." ;;
esac

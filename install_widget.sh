#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  KCpuFreq — Widget installer / updater for KDE Plasma 6
#  Installs or live-updates the widget via kpackagetool6
#  NOTE: Does NOT touch the running plasmashell — restart manually after install
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID="${SCRIPT_DIR}/kcpufreq.plasmoid"
WIDGET_ID="org.kde.plasma.kcpufreq"
USER_PLASMOID_DIR="${HOME}/.local/share/plasma/plasmoids/${WIDGET_ID}"
ICON_INSTALL_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"

step()  { echo -e "${GREEN}▶${NC} ${BOLD}$*${NC}"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
err()   { echo -e "${RED}✗${NC}  $*"; exit 1; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
info()  { echo -e "   $*"; }

echo -e "${CYAN}${BOLD}  KCpuFreq — Plasma Widget Installer${NC}"
echo "  ────────────────────────────────────"
echo ""

# ── 1. Check KDE Plasma 6 ────────────────────────────────────────────────────
step "Checking KDE Plasma version..."
if command -v plasmashell &>/dev/null; then
    PLASMA_VER=$(plasmashell --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
    info "plasmashell ${PLASMA_VER}"
    PLASMA_MAJOR=$(echo "${PLASMA_VER}" | cut -d. -f1)
    if [[ "${PLASMA_MAJOR}" != "6" ]]; then
        warn "Detected Plasma ${PLASMA_MAJOR} — this widget targets Plasma 6. Proceeding anyway."
    else
        ok "Plasma 6 detected"
    fi
else
    warn "plasmashell not found in PATH — continuing anyway"
fi

# ── 2. Build if .plasmoid missing ────────────────────────────────────────────
if [[ ! -f "${PLASMOID}" ]]; then
    step "No .plasmoid found — building first..."
    bash "${SCRIPT_DIR}/build_widget.sh"
fi
ok ".plasmoid found: ${PLASMOID}"

# ── 3. Ensure kpackagetool6 is available ─────────────────────────────────────
step "Checking kpackagetool6..."
if ! command -v kpackagetool6 &>/dev/null; then
    step "Installing plasma-framework (provides kpackagetool6)..."
    sudo pacman -S --noconfirm --needed plasma-framework || \
        sudo pacman -S --noconfirm --needed kf6-plasma || \
        err "Could not install kpackagetool6. Install plasma-framework manually."
fi
ok "kpackagetool6: $(command -v kpackagetool6)"

# ── 4. Install / upgrade widget ──────────────────────────────────────────────
step "Installing KCpuFreq widget into user session..."

# Always force-remove first so no stale QML files survive an upgrade
PLASMOID_DIR="${HOME}/.local/share/plasma/plasmoids/${WIDGET_ID}"
if [[ -d "${PLASMOID_DIR}" ]]; then
    info "Removing existing installation to ensure clean install..."
    kpackagetool6 --type Plasma/Applet --remove "${WIDGET_ID}" 2>/dev/null || true
    # Belt-and-suspenders: also nuke the directory directly
    rm -rf "${PLASMOID_DIR}"
    ok "Removed old installation"
fi

info "Installing fresh..."
kpackagetool6 --type Plasma/Applet --install "${PLASMOID}" 2>/dev/null && ok "Widget installed"

# ── 5. Install custom icon ───────────────────────────────────────────────────
step "Installing KCpuFreq icon..."
ICON_SRC="${SCRIPT_DIR}/cpufreq-widget/contents/icons/kcpufreq.svg"
if [[ -f "${ICON_SRC}" ]]; then
    mkdir -p "${ICON_INSTALL_DIR}"
    cp "${ICON_SRC}" "${ICON_INSTALL_DIR}/kcpufreq.svg"

    # Also copy into the installed plasmoid directory
    mkdir -p "${USER_PLASMOID_DIR}/contents/icons"
    cp "${ICON_SRC}" "${USER_PLASMOID_DIR}/contents/icons/kcpufreq.svg"

    # Refresh KDE sycoca (icon/service cache) — safe, does not touch plasmashell
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 2>/dev/null || true
    fi
    ok "Icon installed"
else
    warn "Icon SVG not found at ${ICON_SRC} — using fallback"
fi

# ── 6. Verify installation ───────────────────────────────────────────────────
step "Verifying installation..."
if [[ -d "${USER_PLASMOID_DIR}" ]]; then
    ok "Widget files present: ${USER_PLASMOID_DIR}"
else
    warn "Widget directory not found — installation may have failed"
fi

echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}Installation complete!${NC}"
echo ""
echo -e "  ${BOLD}Log out and log back in to activate the widget.${NC}"
echo ""
echo -e "  ${BOLD}Then add the widget:${NC}"
echo "   1. Right-click the desktop → Add Widgets"
echo "   2. Search for 'KCPUFreq'"
echo "   3. Drag it to your panel or desktop"
echo ""
echo -e "  ${YELLOW}Tip:${NC} First use may prompt for pkexec password."
echo -e "  Run ${BOLD}./install_cpufreq_backend.sh${NC} to enable passwordless operation."
echo ""

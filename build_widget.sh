#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  KCpuFreq — Widget build script
#  Packages cpufreq-widget/ into kcpufreq.plasmoid (a zip archive)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_SRC="${SCRIPT_DIR}/cpufreq-widget"
OUTPUT="${SCRIPT_DIR}/kcpufreq.plasmoid"

step()  { echo -e "${GREEN}▶${NC} ${BOLD}$*${NC}"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
err()   { echo -e "${RED}✗${NC}  $*"; exit 1; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }

echo -e "${CYAN}${BOLD}  KCpuFreq — Widget Builder${NC}"
echo "  ──────────────────────────────"
echo ""

# ── validate source ───────────────────────────────────────────────────────────
step "Checking widget source directory..."
[[ -d "${WIDGET_SRC}" ]]                       || err "Widget source not found: ${WIDGET_SRC}"
[[ -f "${WIDGET_SRC}/metadata.json" ]]         || err "metadata.json missing"
[[ -f "${WIDGET_SRC}/contents/ui/main.qml" ]]  || err "contents/ui/main.qml missing"
[[ -f "${WIDGET_SRC}/contents/icons/kcpufreq.svg" ]] || warn "Icon SVG not found — widget will use fallback icon"
ok "Source validated"

# ── check dependencies ────────────────────────────────────────────────────────
step "Checking build dependencies..."
command -v zip &>/dev/null || { step "Installing zip..."; sudo pacman -S --noconfirm --needed zip; }
ok "zip available"

# ── clean previous build ──────────────────────────────────────────────────────
step "Cleaning previous build..."
rm -f "${OUTPUT}"
ok "Clean"

# ── package ───────────────────────────────────────────────────────────────────
step "Packaging widget into ${OUTPUT}..."
cd "${WIDGET_SRC}"
zip -r "${OUTPUT}" . \
    --exclude "*.pyc" \
    --exclude "__pycache__/*" \
    --exclude ".git/*" \
    --exclude "*.swp"
cd "${SCRIPT_DIR}"

# ── verify ────────────────────────────────────────────────────────────────────
step "Verifying package..."
SIZE=$(du -sh "${OUTPUT}" | cut -f1)
FILES=$(unzip -l "${OUTPUT}" | tail -1 | awk '{print $2}')
ok "Built: ${OUTPUT} (${SIZE}, ${FILES} files)"

echo ""
echo -e "  ${BOLD}Manifest:${NC}"
unzip -l "${OUTPUT}" | grep -v "^Archive" | head -30

echo ""
echo -e "${CYAN}─────────────────────────────────────────${NC}"
echo -e "${BOLD}Build complete!${NC}"
echo ""
echo -e "  Run ${BOLD}./install_widget.sh${NC} to install into KDE Plasma."
echo ""

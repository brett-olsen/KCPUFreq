#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  KCpuFreq — Backend installer for Arch Linux / Garuda
#  Installs: cpufrequtils, cpupower, polkit rules for passwordless freq control
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    echo -e "${CYAN}"
    echo "  ██╗  ██╗ ██████╗██████╗ ██╗   ██╗███████╗██████╗ ███████╗ ██████╗"
    echo "  ██║ ██╔╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗██╔════╝██╔═══██╗"
    echo "  █████╔╝ ██║     ██████╔╝██║   ██║█████╗  ██████╔╝█████╗  ██║   ██║"
    echo "  ██╔═██╗ ██║     ██╔═══╝ ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██║▄▄ ██║"
    echo "  ██║  ██╗╚██████╗██║     ╚██████╔╝██║     ██║  ██║███████╗╚██████╔╝"
    echo "  ╚═╝  ╚═╝ ╚═════╝╚═╝      ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝ ╚══▀▀═╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}KCpuFreq Backend Installer${NC} — Arch Linux / Garuda"
    echo "  ─────────────────────────────────────────────────────"
    echo ""
}

step() { echo -e "${GREEN}▶${NC} ${BOLD}$*${NC}"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC}  $*"; exit 1; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }

banner

# ── 1. Check we're on Arch/Garuda ────────────────────────────────────────────
step "Checking system..."
if ! command -v pacman &>/dev/null; then
    err "pacman not found. This script is for Arch Linux / Garuda only."
fi
ok "Arch/Garuda detected"

# ── 2. Install packages ───────────────────────────────────────────────────────
# Note: cpufrequtils is Debian/Ubuntu only. On Arch, cpupower (from linux-tools)
# provides cpupower, cpufreq-set, and cpufreq-info as the full equivalent.
step "Installing cpupower and tools via pacman..."
sudo pacman -S --noconfirm --needed \
    cpupower \
    polkit \
    dmidecode \
    bc
ok "Packages installed"

# ── 3. Enable cpupower service ────────────────────────────────────────────────
step "Enabling cpupower systemd service..."
sudo systemctl enable --now cpupower.service && ok "cpupower.service enabled and started" \
    || warn "cpupower.service failed to start (may need reboot or kernel module)"

# ── 4. Install polkit rule — passwordless cpufreq-set for wheel group ─────────
step "Installing polkit rules for passwordless CPU frequency control..."

POLKIT_RULES_DIR="/etc/polkit-1/rules.d"
POLKIT_RULE_FILE="${POLKIT_RULES_DIR}/90-kcpufreq.rules"

sudo mkdir -p "${POLKIT_RULES_DIR}"

sudo tee "${POLKIT_RULE_FILE}" > /dev/null << 'POLKIT_EOF'
// KCpuFreq polkit rule
// Allows members of the 'wheel' group to set CPU frequency
// without password prompts (required for Plasma widget operation)
polkit.addRule(function(action, subject) {
    var allowedActions = [
        "org.freedesktop.policykit.exec"
    ];
    if (allowedActions.indexOf(action.id) !== -1 &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
POLKIT_EOF

ok "polkit rule installed at ${POLKIT_RULE_FILE}"

# ── 5. Install udev rule for /sys CPU freq write access ───────────────────────
step "Installing udev rule for sysfs CPU frequency write permissions..."

UDEV_RULE_FILE="/etc/udev/rules.d/90-kcpufreq-cpu.rules"

sudo tee "${UDEV_RULE_FILE}" > /dev/null << 'UDEV_EOF'
# KCpuFreq udev rules
# Allow wheel group to write CPU frequency/governor/turbo settings via sysfs
SUBSYSTEM=="cpu", ACTION=="add|change", RUN+="/bin/chmod 664 /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
SUBSYSTEM=="cpu", ACTION=="add|change", RUN+="/bin/chmod 664 /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq"
SUBSYSTEM=="cpu", ACTION=="add|change", RUN+="/bin/chmod 664 /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq"
SUBSYSTEM=="cpu", ACTION=="add|change", RUN+="/bin/chmod 664 /sys/devices/system/cpu/cpu*/online"
UDEV_EOF

ok "udev rule installed at ${UDEV_RULE_FILE}"

# ── 6. Reload udev ────────────────────────────────────────────────────────────
step "Reloading udev rules..."
sudo udevadm control --reload-rules && sudo udevadm trigger && ok "udev reloaded" || warn "udev reload failed, reboot recommended"

# ── 7. Verify freq tools are available ───────────────────────────────────────
step "Verifying CPU frequency tools..."
if command -v cpufreq-set &>/dev/null; then
    ok "cpufreq-set found: $(command -v cpufreq-set)"
elif command -v cpupower &>/dev/null; then
    ok "cpupower found: $(command -v cpupower)  (used as cpufreq-set equivalent)"
    # Create a thin cpufreq-set shim so the widget's pkexec calls work unchanged
    if [[ ! -f /usr/local/bin/cpufreq-set ]]; then
        sudo tee /usr/local/bin/cpufreq-set > /dev/null << 'SHIM_EOF'
#!/usr/bin/env bash
# Thin shim: translates cpufreq-set flags to cpupower frequency-set
# cpufreq-set -c <core> -g <gov>    → cpupower -c <core> frequency-set -g <gov>
# cpufreq-set -c <core> -d <min>    → cpupower -c <core> frequency-set -d <min>
# cpufreq-set -c <core> -u <max>    → cpupower -c <core> frequency-set -u <max>
CORE=""
GOV=""
MIN=""
MAX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c) CORE="$2"; shift 2 ;;
        -g) GOV="$2";  shift 2 ;;
        -d) MIN="$2";  shift 2 ;;
        -u) MAX="$2";  shift 2 ;;
        *)  shift ;;
    esac
done
ARGS=()
[[ -n "$CORE" ]] && ARGS+=(-c "$CORE")
[[ -n "$GOV"  ]] && ARGS+=(frequency-set -g "$GOV")
[[ -n "$MIN"  ]] && ARGS+=(frequency-set -d "$MIN")
[[ -n "$MAX"  ]] && ARGS+=(frequency-set -u "$MAX")
exec cpupower "${ARGS[@]}"
SHIM_EOF
        sudo chmod +x /usr/local/bin/cpufreq-set
        ok "cpufreq-set shim installed at /usr/local/bin/cpufreq-set"
    fi
else
    warn "Neither cpufreq-set nor cpupower found — frequency setting will not work"
fi

# ── 8. Quick smoke test ───────────────────────────────────────────────────────
step "Smoke test: reading current governor..."
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unreadable")
ok "CPU0 governor: ${GOV}"

FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
if [ "${FREQ}" != "0" ]; then
    MHZ=$(echo "scale=2; ${FREQ} / 1000" | bc)
    ok "CPU0 current freq: ${MHZ} MHz"
fi

echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}Backend installation complete!${NC}"
echo ""
echo -e "  ${YELLOW}Note:${NC} If you see pkexec password prompts in the widget,"
echo "  log out and back in so polkit picks up the new rules."
echo ""
echo -e "  Run ${BOLD}./install_widget.sh${NC} next to install the KCpuFreq widget."
echo ""

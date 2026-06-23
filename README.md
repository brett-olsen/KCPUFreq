# KCPUFreq

A KDE Plasma 6 widget for CPU frequency and power management on Arch Linux / Garuda.

![KCPUFreq Widget](screenshot.png)

## Features

- Live per-core frequency display with mini activity bars and real-time graph
- Governor and Power Profile selection
- Min/Max frequency sliders with apply confirmation
- Cores Online slider (hot-plug CPU cores)
- Turbo Boost toggle (Intel + AMD)
- System Load and Memory bars
- Live graph — Temperature, Load, and Frequency traces
- **Overview** and **Options** tabs
- Tint colour picker (10 presets)
- Configurable font family and size for titlebar and application
- Optional CPU frequency display in taskbar
- Adjustable refresh rate (1–30s)
- Settings persist across sessions

## Requirements

- KDE Plasma 6 (tested on 6.7+)
- Arch Linux / Garuda (or any distro with `cpupower`)
- `plasma5support` KF6 package
- `polkit` for passwordless sysfs writes

## Install from GitHub

```bash
# Clone the repo
git clone https://github.com/brett-olsen/KCPUFreq.git
cd KCPUFreq

# 1. Install backend tools and polkit rules (run once, requires sudo)
./install_cpufreq_backend.sh

# 2. Build the .plasmoid package
./build_widget.sh

# 3. Install into Plasma
./install_widget.sh

# 4. Restart plasmashell
kquitapp6 plasmashell && kstart6 plasmashell
```

Then right-click your desktop → **Add Widgets** → search **KCPUFreq**.

## Update

```bash
git pull
./build_widget.sh && ./install_widget.sh
kquitapp6 plasmashell && kstart6 plasmashell
```

## Uninstall

```bash
kpackagetool6 --type Plasma/Applet --remove org.kde.plasma.kcpufreq
```

## Options Tab

- **Titlebar** — font family, size, and CPU speed toggle with live preview
- **Application** — font family and size for all widget text
- **Tint Color** — 10 colour presets applied to accents, bars, and graph
- **Graph** — Large (full-width below both columns) or Small (right column)
- **Polling** — refresh rate 1–30s

## Author

**Brett Olsen** — [github.com/brett-olsen](https://github.com/brett-olsen)  
[https://github.com/brett-olsen/KCPUFreq](https://github.com/brett-olsen/KCPUFreq)

## License

MIT

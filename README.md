# KCPUFreq

A KDE Plasma 6 widget for CPU frequency and power management on Arch Linux / Garuda.

<img width="588" height="765" alt="image" src="https://github.com/user-attachments/assets/2d110c2a-9c54-4c08-a440-34146bf8cfac" />



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
- Solid and System background styling
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

# 1. Make the helper scripts executable
chmod +x ./*.sh
# 2. Install backend tools and polkit rules (run once, requires sudo)
./install_cpufreq_backend.sh

# 3. Build the .plasmoid package
./build_widget.sh

# 4. Install into Plasma
./install_widget.sh

```

If the widget does not show, you may need to either restart your plasma desktop, or simply logout/back in. Then right-click your desktop → **Add Widgets** → search **KCPUFreq**.

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

## Overview Tab

- **Power Profile** — powersave, balanced, performance 
- **Governor** — conservative, ondemand, userspace, powersave, performance, scchedutil 
- **Minimum** — slider for the minimum CPU speed in Mhz
- **Maximum** — slider for the maximum CPU speed in Mhz
- **Cores Online** — slider to set the number of active cores
- **Turbo Boost** — slider to toggle turbo on/off
- **Remember Setttings** — toggle to save/restore application settings on widget load
some options may vary, depending on your CPU, Kernel, etc

## Options Tab

- **Titlebar** — font family, size, and CPU speed toggle with live preview
- **Application** — font family and size for all widget text
- **Tint Color** — 10 colour presets applied to accents, bars, and graph
- **Polling** — refresh rate 1–30s
- **Page Background** — choose between solid, or system
- **Graph** — Large (full-width below both columns) or Small (embedded right column)


## Author

**Brett Olsen** — [github.com/brett-olsen](https://github.com/brett-olsen)  
[https://github.com/brett-olsen/KCPUFreq](https://github.com/brett-olsen/KCPUFreq)

## License

MIT

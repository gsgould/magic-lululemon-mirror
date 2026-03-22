# Lululemon Mirror Setup

Turn a Lululemon Mirror (or any smart mirror) into a MagicMirror + AirPlay display using a Raspberry Pi 4.

**When idle**, the mirror shows a clock and motivational messages. **When you AirPlay from your phone**, it automatically switches to fullscreen mirroring for workout apps. **When you stop casting**, it switches back.

## What You Need

- Raspberry Pi 4 (4GB+ recommended)
- MicroSD card (16GB+)
- Lululemon Mirror (or any display behind a two-way mirror)
- HDMI cable
- iPhone or iPad for AirPlay

## Quick Start

### 1. Flash Raspberry Pi OS

Download [Raspberry Pi OS Lite (64-bit, Bookworm)](https://www.raspberrypi.com/software/) using Raspberry Pi Imager. In the imager settings, configure:

- WiFi credentials
- SSH enabled
- Hostname (e.g. `mirror`)
- Username and password

Flash to SD card and boot the Pi.

### 2. SSH in and run setup

```bash
ssh your-user@mirror.local
git clone https://github.com/YOUR_USERNAME/magic-mirror-setup.git
cd magic-mirror-setup
chmod +x setup.sh
./setup.sh
```

### 3. Reboot

```bash
sudo reboot
```

After ~20 seconds, the mirror display will show MagicMirror. Open Control Center on your iPhone, tap Screen Mirroring, and select "Mirror" to start casting.

## What the Setup Script Does

The entire setup is a single self-contained `setup.sh` that:

1. **Updates the system** and configures boot settings (GPU memory, disable Bluetooth)
2. **Installs a minimal X11 environment** — Openbox, Chromium, PulseAudio, cursor hiding
3. **Disables unnecessary services** for faster boot (triggerhappy, apt timers, etc.)
4. **Sets CPU governor to performance** and installs zram for faster swap
5. **Installs Node.js and MagicMirror** in server-only mode (no Electron)
6. **Writes the MagicMirror config** with clock, workout prompt, and compliments
7. **Installs uxplay** for AirPlay mirroring with hardware-accelerated video decoding
8. **Installs the auto-switch script** that detects AirPlay connections and toggles between MagicMirror and the AirPlay stream
9. **Installs a MagicMirror watchdog** that restarts it if it crashes
10. **Configures log rotation** to prevent log files from filling the SD card
11. **Sets up Openbox autostart** with splash screen, 720p portrait mode, kiosk Chromium, and HDMI audio via PulseAudio
12. **Configures auto-login** so everything starts on boot without interaction

The script is idempotent — safe to run multiple times.

## How Auto-Switching Works

The `mirror-switch.sh` script:

1. Starts uxplay in the background (fullscreen mode)
2. Polls every 2 seconds for active TCP connections to uxplay using `ss`
3. When an AirPlay connection is detected:
   - Hides and freezes Chromium (frees CPU)
4. When the AirPlay connection drops:
   - Unfreezes Chromium and brings it to the front
5. If uxplay crashes, it automatically restarts

## Display Configuration

The display is set to **720p portrait mode** via `xrandr`. The connected HDMI output is auto-detected. To adjust:

- **Resolution**: Edit `~/.config/openbox/autostart` — change `--mode 1280x720` to your preferred resolution
- **Rotation**: Change `--rotate left` to `right`, `normal`, or `inverted`

## Customization

### MagicMirror Modules

Edit `~/MagicMirror/config/config.js` on the Pi. The default config includes:

- **Clock** (top center)
- **Workout prompt** (upper third) — "Hey Greg, ready to workout?"
- **Compliments** (lower third) — rotating motivational messages

See the [MagicMirror module directory](https://modules.magicmirror.builders/) for hundreds of community modules.

### AirPlay Device Name

The AirPlay device appears as "Mirror" on your phone. To change it, edit `~/mirror-switch.sh` and modify the `-n "Mirror"` flag.

### Workout Prompt

Edit the `workout-prompt` section in `config.js` to change the header text or casting instructions. Styling is in `~/MagicMirror/css/custom.css`.

## Logs

```bash
# AirPlay auto-switch log
tail -f /tmp/mirror-switch.log

# MagicMirror watchdog log
tail -f /tmp/mm-watchdog.log
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Display is upside down | Change `--rotate left` to `--rotate right` in `~/.config/openbox/autostart` |
| AirPlay not visible on iPhone | Check avahi is running: `sudo systemctl status avahi-daemon` |
| No audio over HDMI | Check PulseAudio: `pactl list sinks short`, unsuspend with `pactl suspend-sink 0 0` |
| MagicMirror won't start | Check `node -v` (needs 18+), try `cd ~/MagicMirror && npm install` |
| Black screen after boot | Check `~/.local/share/xorg/Xorg.0.log` for X11 errors |
| Auto-switch not working | Check `tail -f /tmp/mirror-switch.log` and `ss -tnp \| grep uxplay` |
| Pi is slow or laggy | Try lowering resolution in autostart, ensure `gpu_mem=256` is in `/boot/firmware/config.txt` |
| Can't SSH after reboot | The Pi may be frozen; power cycle and check WiFi config |

## Architecture

```
Boot
 └─ Auto-login (console)
     └─ startx (from .bash_profile)
         └─ Openbox
             ├─ xrandr (720p portrait, auto-detect HDMI)
             ├─ PulseAudio (HDMI audio output)
             ├─ unclutter (hide cursor)
             ├─ xset (disable screen blanking)
             ├─ mm-watchdog.sh
             │   └─ MagicMirror (node serveronly, port 8080)
             ├─ Chromium (kiosk mode → localhost:8080)
             └─ mirror-switch.sh
                 └─ uxplay (AirPlay receiver)
```

## License

MIT

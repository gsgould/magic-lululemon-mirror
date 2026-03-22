#!/bin/bash
# setup.sh — Single-file setup for MagicMirror + RPiPlay on Raspberry Pi 4
# Designed for Raspberry Pi OS Lite (Bookworm, 64-bit).
# Usage: chmod +x setup.sh && ./setup.sh
#
# After running, reboot the Pi. MagicMirror will launch automatically.
# AirPlay to "Mirror" from your phone to cast; it auto-switches back when you stop.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ============================================================
# Step 1: System update
# ============================================================
info "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# ============================================================
# Step 2: Boot config — GPU memory, disable Bluetooth
# ============================================================
info "Configuring boot settings..."
CONFIG_TXT="/boot/firmware/config.txt"

if ! grep -q "^gpu_mem=" "$CONFIG_TXT" 2>/dev/null; then
    echo "gpu_mem=256" | sudo tee -a "$CONFIG_TXT" > /dev/null
    info "Set gpu_mem=256"
fi

if ! grep -q "^dtoverlay=disable-bt" "$CONFIG_TXT" 2>/dev/null; then
    echo "dtoverlay=disable-bt" | sudo tee -a "$CONFIG_TXT" > /dev/null
    info "Disabled Bluetooth"
fi

# ============================================================
# Step 3: Install X11, Chromium, and utilities
# ============================================================
info "Installing X11, Openbox, Chromium, and utilities..."
sudo apt install -y xserver-xorg xinit openbox chromium unclutter wmctrl pulseaudio

# Disable unnecessary services
sudo systemctl disable hciuart 2>/dev/null || true
sudo systemctl disable triggerhappy 2>/dev/null || true
sudo systemctl disable keyboard-setup 2>/dev/null || true
sudo systemctl disable raspi-config 2>/dev/null || true
sudo systemctl disable apt-daily.timer 2>/dev/null || true
sudo systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
sudo systemctl disable man-db.timer 2>/dev/null || true


# Set CPU to performance mode
info "Set CPU governor to performance"

# Disable WiFi power management (prevents micro-lag)
sudo iw wlan0 set power_save off 2>/dev/null || true

# Install zram for faster swap
sudo apt install -y zram-tools
info "Installed zram for swap"

# ============================================================
# Step 4: Install Node.js LTS
# ============================================================
info "Installing Node.js LTS..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    info "Node.js already installed: $(node -v)"
fi

sudo apt install -y git

# ============================================================
# Step 5: Install MagicMirror
# ============================================================
info "Installing MagicMirror..."
if [ ! -d "$HOME/MagicMirror" ]; then
    cd ~
    git clone https://github.com/MagicMirrorOrg/MagicMirror.git
    cd MagicMirror
    npm run install-mm
else
    info "MagicMirror directory already exists, skipping clone"
    cd ~/MagicMirror
    npm install
fi

# ============================================================
# Step 6: Write MagicMirror config
# ============================================================
info "Writing MagicMirror config..."

cat > "$HOME/MagicMirror/config/config.js" << 'MMCONFIG'
/* MagicMirror config for Lululemon Mirror (portrait mode)
 *
 * Modules: clock, compliments
 * Layout optimized for a tall, narrow mirror display.
 */

let config = {
	address: "0.0.0.0",
	port: 8080,
	basePath: "/",
	ipWhitelist: [],
	language: "en",
	locale: "en-US",
	timeFormat: 12,
	units: "metric",

	modules: [
		// --- Top bar: Clock ---
		{
			module: "clock",
			position: "top_center",
			config: {
				dateFormat: "dddd, MMMM D",
				showSunTimes: false,
				showWeek: false,
			}
		},

		// --- Middle: Workout prompt ---
		{
			module: "compliments",
			position: "upper_third",
			classes: "workout-prompt",
			header: "Open up your screen casting and select \"Mirror\" to start your session.",
			config: {
				compliments: {
					anytime: [
						"Hey Greg, ready to workout?",
					],
				}
			}
		},

		// --- Lower third: Compliments ---
		{
			module: "compliments",
			position: "lower_third",
			config: {
				compliments: {
					anytime: [
						"You look great today!",
						"Keep going, you're doing amazing.",
						"Stay strong.",
					],
					morning: [
						"Good morning!",
						"Rise and shine!",
						"Today is a new opportunity.",
					],
					afternoon: [
						"Keep up the great work!",
						"You're crushing it today.",
					],
					evening: [
						"Time to wind down.",
						"You earned this rest.",
						"Great job today!",
					],
				}
			}
		},
	]
};

/*************** DO NOT EDIT THE LINE BELOW ***************/
if (typeof module !== "undefined") { module.exports = config; }
MMCONFIG
info "MagicMirror config written"

# ============================================================
# Step 7: Install uxplay (AirPlay mirroring server)
# ============================================================
info "Installing uxplay..."
sudo apt install -y uxplay

# ============================================================
# Step 8: Write mirror-switch.sh (AirPlay auto-switch script)
# ============================================================
info "Writing mirror-switch.sh..."
cat > "$HOME/mirror-switch.sh" << 'SWITCHSCRIPT'
#!/bin/bash
# mirror-switch.sh
# Runs uxplay and auto-switches between MagicMirror (Chromium) and AirPlay.
# Polls for active connections to uxplay to detect AirPlay connect/disconnect.

export DISPLAY=:0

LOG_FILE="/tmp/mirror-switch.log"
POLL_INTERVAL=2
AIRPLAY_ACTIVE=false

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Show MagicMirror (unfreeze Chromium and bring to front)
show_mm() {
    log "Showing MagicMirror"
    pkill -CONT -f chromium 2>/dev/null
    wmctrl -a "Chromium" 2>/dev/null
}

# Hide MagicMirror (minimize and freeze Chromium to free CPU)
hide_mm() {
    log "Hiding MagicMirror"
    wmctrl -r "Chromium" -b add,hidden 2>/dev/null
    sleep 1
    pkill -STOP -f chromium 2>/dev/null
}

log "Starting mirror-switch — launching uxplay..."

# Start uxplay in the background (-fs for fullscreen)
uxplay -n "Mirror" -fs -reset 0 &
UXPLAY_PID=$!
log "uxplay started (PID: $UXPLAY_PID)"

# Wait for uxplay to initialize
sleep 3

# Poll for active AirPlay connections by checking if uxplay has
# established TCP connections (beyond its listening sockets)
while kill -0 "$UXPLAY_PID" 2>/dev/null; do
    CONNECTIONS=$(ss -tnp 2>/dev/null | grep "uxplay" | grep "ESTAB" | wc -l)

    if [ "$CONNECTIONS" -gt 0 ] && [ "$AIRPLAY_ACTIVE" = false ]; then
        log "AirPlay connected ($CONNECTIONS active connections)"
        AIRPLAY_ACTIVE=true
        hide_mm
    elif [ "$CONNECTIONS" -eq 0 ] && [ "$AIRPLAY_ACTIVE" = true ]; then
        log "AirPlay disconnected"
        AIRPLAY_ACTIVE=false
        show_mm
    fi

    sleep "$POLL_INTERVAL"
done

# If uxplay exits while AirPlay was active, show MagicMirror
if [ "$AIRPLAY_ACTIVE" = true ]; then
    log "uxplay crashed during active session"
    AIRPLAY_ACTIVE=false
    show_mm
fi

log "uxplay exited, restarting..."
exec "$0"
SWITCHSCRIPT
chmod +x "$HOME/mirror-switch.sh"
info "mirror-switch.sh installed"

# ============================================================
# Step 9: Write MagicMirror watchdog script
# ============================================================
info "Writing mm-watchdog.sh..."
cat > "$HOME/mm-watchdog.sh" << 'WATCHDOG'
#!/bin/bash
# mm-watchdog.sh — Restarts MagicMirror if it crashes
LOG_FILE="/tmp/mm-watchdog.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

while true; do
    log "Starting MagicMirror..."
    cd ~/MagicMirror && node serveronly 2>&1 | tail -50 >> "$LOG_FILE"
    log "MagicMirror exited, restarting in 3 seconds..."
    sleep 3
done
WATCHDOG
chmod +x "$HOME/mm-watchdog.sh"
info "mm-watchdog.sh installed"

# ============================================================
# Step 10: Configure log rotation
# ============================================================
info "Configuring log rotation..."
sudo tee /etc/logrotate.d/mirror << 'LOGROTATE' > /dev/null
/tmp/mirror-switch.log /tmp/mm-watchdog.log {
    size 1M
    rotate 2
    missingok
    notifempty
    copytruncate
}
LOGROTATE
info "Log rotation configured"

# ============================================================
# Step 11: Write Openbox autostart
# ============================================================
info "Configuring Openbox autostart..."
mkdir -p "$HOME/.config/openbox"
cat > "$HOME/.config/openbox/autostart" << 'AUTOSTART'
# Openbox autostart — launched when X11 starts

# Set resolution to 720p and rotate to portrait (detect which HDMI port is connected)
HDMI_OUTPUT=$(xrandr | grep ' connected' | awk '{print $1}' | head -1)
xrandr --output "$HDMI_OUTPUT" --mode 1280x720 --rotate left

# Set CPU governor to performance
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null

# Hide cursor
unclutter -idle 0.5 -root &

# Disable screen blanking and power management
xset s off
xset -dpms
xset s nofade

# Start PulseAudio and unsuspend HDMI audio sink
pulseaudio --start
sleep 1
pactl suspend-sink 0 0

# Show splash screen while loading
xmessage -center -bg black -fg white -fn '-*-helvetica-bold-r-*-*-24-*-*-*-*-*-*-*' "Loading..." &
SPLASH_PID=$!

# Start MagicMirror in server-only mode with watchdog
~/mm-watchdog.sh &

# Wait for MagicMirror server to be ready (poll instead of fixed sleep)
while ! curl -s http://localhost:8080 > /dev/null 2>&1; do sleep 1; done

# Kill splash screen
kill $SPLASH_PID 2>/dev/null

# Launch Chromium in kiosk mode pointing to MagicMirror
chromium --noerrdialogs --disable-infobars --kiosk \
  --disable-translate --no-first-run --fast --fast-start \
  --disable-features=TranslateUI --disk-cache-dir=/dev/null \
  --disable-gpu-compositing --disable-smooth-scrolling \
  --disable-extensions --disable-background-networking \
  --process-per-site --memory-pressure-off \
  http://localhost:8080 &

# Wait for Chromium window to appear
while ! wmctrl -l 2>/dev/null | grep -q "Chromium"; do sleep 1; done

# Start the RPiPlay auto-switch script
~/mirror-switch.sh &
AUTOSTART
info "Openbox autostart configured"

# ============================================================
# Step 10: Auto-login and X autostart
# ============================================================
info "Setting up auto-login (console autologin)..."
sudo raspi-config nonint do_boot_behaviour B2

if ! grep -q 'startx -- -nocursor' "$HOME/.bash_profile" 2>/dev/null; then
    echo '[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && startx -- -nocursor' >> "$HOME/.bash_profile"
    info "Added startx auto-launch to ~/.bash_profile"
else
    info "startx already configured in .bash_profile"
fi

# ============================================================
# Done!
# ============================================================
echo ""
info "========================================="
info "Setup complete!"
info "========================================="
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. After ~20 seconds, MagicMirror should appear on the display"
echo "  3. Test AirPlay from your iPhone (Control Center → Screen Mirroring → 'Mirror')"
echo "  4. Logs: tail -f /tmp/mirror-switch.log"
echo ""
warn "If the display is upside down, edit ~/.config/openbox/autostart and change 'rotate left' to 'rotate right'"

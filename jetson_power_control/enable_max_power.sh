#!/usr/bin/env bash
set -euo pipefail

TOP_MODE="${TOP_MODE:-2}"     # MAXN_SUPER on your board
FAN_PROFILE="${FAN_PROFILE:-cool}"  # nvfancontrol profile: quiet|cool|... (from /etc/nvfancontrol.conf)

# Re-run as root if needed
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

echo "[*] Ensuring a baseline exists for jetson_clocks --restore..."
if [[ ! -f /root/.jetsonclocks_conf.txt ]]; then
  jetson_clocks --store
fi

echo "[*] Switching to MAX power mode (ID ${TOP_MODE})..."
nvpmodel -m "${TOP_MODE}"

echo "[*] Locking CPU/GPU/EMC clocks (no fan pin)..."
jetson_clocks

# Make sure automatic fan control is active and using a reasonable profile
if systemctl list-unit-files | grep -q '^nvfancontrol\.service'; then
  echo "[*] Enabling & restarting nvfancontrol with '${FAN_PROFILE}' profile..."
  # Set default profile in config (idempotent)
  if [[ -f /etc/nvfancontrol.conf ]]; then
    sed -i 's/^FAN_DEFAULT_PROFILE .*/FAN_DEFAULT_PROFILE '"${FAN_PROFILE}"'/g' /etc/nvfancontrol.conf || true
  fi
  systemctl unmask nvfancontrol || true
  systemctl enable nvfancontrol || true
  rm -f /var/lib/nvfancontrol/status || true
  systemctl restart nvfancontrol
fi

echo "[*] Keep GPU awake during workload (optional)..."
echo on > /sys/devices/platform/gpu.0/power/control || true

echo "[*] Optional: set CPU governors to 'performance' for absolute consistency"
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [[ -f "$g" ]] && echo performance > "$g" || true
done

echo "------------------ STATUS ------------------"
nvpmodel -q || true
jetson_clocks --show || true
systemctl status --no-pager nvfancontrol 2>/dev/null | sed -n '1,6p' || true
echo "--------------------------------------------"
echo "[✓] Max performance enabled with nvfancontrol managing fans."

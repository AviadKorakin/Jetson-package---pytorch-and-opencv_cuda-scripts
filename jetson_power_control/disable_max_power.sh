#!/usr/bin/env bash
set -euo pipefail

RESTORE_MODE="${RESTORE_MODE:-0}"   # Always go back to 15W (ID 0 on your board)

# Re-run as root if needed
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

echo "[*] Restoring clocks/fan from stored baseline if present..."
if [[ -f /root/.jetsonclocks_conf.txt ]]; then
  jetson_clocks --restore || true
else
  # Minimal safe fallback if no baseline existed
  jetson_clocks --restore || true
fi

echo "[*] Re-enabling automatic fan control (sysfs + nvfancontrol)..."
# Hand control back to thermal governor via sysfs (no-op if different path)
for d in \
  /sys/devices/platform/pwm-fan/hwmon/hwmon* \
  /sys/devices/pwm-fan/hwmon/hwmon* \
  /sys/class/hwmon/hwmon*; do
  [[ -d "$d" ]] || continue
  [[ -f "$d/pwm1_enable" ]] && echo 2 > "$d/pwm1_enable" || true   # 2 = auto
  [[ -f "$d/pwm1" ]]         && echo 0 > "$d/pwm1" || true
done
for c in /sys/devices/virtual/thermal/cooling_device*; do
  [[ -f "$c/type" ]] || continue
  if grep -iq 'pwm-fan' "$c/type"; then
    [[ -f "$c/cur_state" ]] && echo 0 > "$c/cur_state" || true
  fi
done

# Make sure the daemon is actually running again
if systemctl list-unit-files | grep -q '^nvfancontrol\.service'; then
  systemctl unmask nvfancontrol || true
  systemctl enable nvfancontrol || true
  rm -f /var/lib/nvfancontrol/status || true
  systemctl restart nvfancontrol
fi

echo "[*] Returning GPU runtime PM/devfreq & EMC caps to defaults..."
echo auto > /sys/devices/platform/gpu.0/power/control || true
GF_DIR="/sys/devices/platform/17000000.gpu/devfreq/17000000.gpu"
[[ -d "$GF_DIR" && -f "$GF_DIR/min_freq" ]] && echo 0 > "$GF_DIR/min_freq" || true
[[ -d "$GF_DIR" && -f "$GF_DIR/max_freq" ]] && echo 9223372036854775807 > "$GF_DIR/max_freq" || true
for p in /sys/kernel/nvpmodel_clk_cap/emc /sys/kernel/nvpmodel_emc_cap/emc; do
  [[ -f "$p" ]] && echo 0 > "$p" || true
done

echo "[*] CPU governors back to schedutil + silicon min/max..."
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
  [[ -d "$cpu" ]] || continue
  gov="$cpu/cpufreq/scaling_governor"
  min="$cpu/cpufreq/scaling_min_freq"
  max="$cpu/cpufreq/scaling_max_freq"
  hwmin="$cpu/cpufreq/cpuinfo_min_freq"
  hwmax="$cpu/cpufreq/cpuinfo_max_freq"
  [[ -f "$gov"  ]] && echo schedutil > "$gov" || true
  [[ -f "$min" && -f "$hwmin" ]] && cat "$hwmin" > "$min" || true
  [[ -f "$max" && -f "$hwmax" ]] && cat "$hwmax" > "$max" || true
done

echo "[*] Switching nvpmodel back to 15W (ID ${RESTORE_MODE})..."
nvpmodel -m "${RESTORE_MODE}" || true

echo "------------------ STATUS ------------------"
nvpmodel -q || true
jetson_clocks --show || true
systemctl status --no-pager nvfancontrol 2>/dev/null | sed -n '1,6p' || true
echo "--------------------------------------------"
echo "[✓] Restored to 15W with automatic, profile-based fan control."

#!/usr/bin/env bash
# 🦇 Gotham Net Auto-Switcher (streaming-tuned)
set -euo pipefail
export LC_ALL=C

# --- SSIDs exactly as shown in OSMC/Kodi (case-sensitive) ---
FIVE_SSID="Batcave"      # 5 GHz
TWO4_SSID="🐢"           # 2.4 GHz
IFACE="wlan0"

# --- State & log ---
STATE_DIR="/var/tmp/wifi_autoswitch"
STATE_TS="$STATE_DIR/last_switch.ts"
STATE_BAD="$STATE_DIR/bad5.count"
STATE_GOOD="$STATE_DIR/good5.count"
LOG="/home/osmc/wifi_autoswitch.log"
mkdir -p "$STATE_DIR"

# --- Streaming “racing stripes” (stability > twitchy ping) ---
MIN_SWITCH_GAP=600   # min seconds between any switches (anti-flap)
NEED_BAD5=1          # leave 5 GHz after this many bad samples
NEED_GOOD5=2         # require this many consecutive goods to return to 5 GHz

# Leave 5 GHz if ANY trips
LEAVE5_RSSI=-70      # dBm (more negative = worse)
LEAVE5_PING=120      # ms
LEAVE5_LOSS=10       # %
LEAVE5_RATE=80       # Mbps (tx bitrate)

# Return to 5 GHz only if ALL pass (hysteresis)
BACK5_RSSI=-60
BACK5_PING=50
BACK5_LOSS=1
BACK5_RATE=120

# Probe
PING_HOST="1.1.1.1"
PING_COUNT=2
PING_TO=1

# --- helpers ---
batlog(){ echo "[$(date '+%F %T')] [BAT-NET] $*" | tee -a "$LOG"; }
ts(){ date +%s; }
last_switch(){ [ -f "$STATE_TS" ] && cat "$STATE_TS" || echo 0; }
can_switch(){ local now=$(ts) last=$(last_switch); [ $((now-last)) -ge $MIN_SWITCH_GAP ]; }
mark_switch(){ ts >"$STATE_TS"; echo 0 >"$STATE_BAD" || true; echo 0 >"$STATE_GOOD" || true; }

toast(){  # title, message, icon
  if command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(${1},${2},5000)" >/dev/null 2>&1 || true
  fi
  batlog "🔔 ${1} — ${2} ${3}"
}

ssid(){  iw dev "$IFACE" link 2>/dev/null | awk -F': ' '/SSID:/ {print $2}' | sed 's/^[[:space:]]*//'; }
rssi(){  iw dev "$IFACE" link 2>/dev/null | awk '/signal:/ {print $2; exit}'; }
freq(){  iw dev "$IFACE" link 2>/dev/null | awk '/freq:/ {print $2;  exit}'; }
rate(){  iw dev "$IFACE" station dump 2>/dev/null | awk '/tx bitrate:/ {print $(NF-1); exit}' | sed 's/\..*//' ; }

ping_stats(){
  local out loss lat
  out=$(ping -c "$PING_COUNT" -W "$PING_TO" "$PING_HOST" 2>/dev/null || true)
  loss=$(awk -F',' '/packet loss/ {gsub(/%/,"",$3); sub(/^ /,"",$3); print int($3)}' <<<"$out")
  lat=$(awk -F'/' '/^rtt/ {print int($5)}' <<<"$out")
  [ -z "${loss:-}" ] && loss=100
  [ -z "${lat:-}" ]  && lat=9999
  echo "$loss $lat"
}

current_service(){
  local s cur_ssid
  cur_ssid="$(ssid || true)"
  [ -z "$cur_ssid" ] && return 1
  s="$(connmanctl services | awk -v q="$cur_ssid" '$0 ~ q {print $NF; exit}')"
  [ -n "$s" ] && echo "$s"
}

connman_id_for(){ connmanctl services | grep -F "$1" | awk '{print $NF}' | head -n1; }

connect_ssid(){
  local target="$1" sid cur
  sid="$(connman_id_for "$target")"
  if [ -z "${sid:-}" ]; then
    batlog "🔎 Scanning for [$target]..."
    connmanctl scan wifi >/dev/null 2>&1 || true
    sid="$(connman_id_for "$target")"
  fi
  if [ -n "${sid:-}" ]; then
    cur="$(current_service || true)"
    if [ -n "${cur:-}" ] && [ "$cur" != "$sid" ]; then
      batlog "🧹 Disconnect current [$cur] before switch"
      connmanctl disconnect "$cur" >/dev/null 2>&1 || true
      sleep 2
    fi
    batlog "🦇 Grapple to [$target] via [$sid]"
    connmanctl connect "$sid" >/dev/null 2>&1 || true
    mark_switch
    sleep 4
    if [ "$target" = "$FIVE_SSID" ]; then
      toast "Bat-Signal" "Boosting to 5 GHz (Batmobile mode)" "🚀"
    else
      toast "Bat-Signal" "Gliding to 2.4 GHz (Stealth mode)" "🐢"
    fi
  else
    batlog "❌  No connman service id for [$target]"
  fi
}

inc(){ local f="$1"; local v=0; [ -f "$f" ] && v=$(cat "$f"); v=$((v+1)); echo "$v" >"$f"; echo "$v"; }
zero(){ echo 0 >"$1"; }

# --- main ---
cur_ssid="$(ssid || true)"
cur_rssi="$(rssi || echo -999)"
cur_freq="$(freq || echo 0)"
cur_rate="$(rate || echo 0)"
read cur_loss cur_ping <<<"$(ping_stats)"

is5=false; [ "${cur_freq:-0}" -ge 4900 ] && is5=true

batlog "ℹ️ ssid='${cur_ssid:-?}' freq=${cur_freq}MHz RSSI=${cur_rssi}dBm tx=${cur_rate}Mbps ping=${cur_ping}ms loss=${cur_loss}% (5GHz=$is5)"

if $is5; then
  # On 5 GHz: leave if ANY bad (plus counter + cooldown)
  if (( cur_rssi <= LEAVE5_RSSI )) || (( cur_ping >= LEAVE5_PING )) || (( cur_loss >= LEAVE5_LOSS )) || (( cur_rate <= LEAVE5_RATE )); then
    bad=$(inc "$STATE_BAD"); zero "$STATE_GOOD"
    batlog "📉 5GHz sample BAD (#$bad)"
    if (( bad >= NEED_BAD5 )) && can_switch; then
      batlog "↘️ Leaving 5GHz → ${TWO4_SSID}"
      connect_ssid "$TWO4_SSID"; exit 0
    fi
  else
    zero "$STATE_BAD"
    batlog "✅  5GHz healthy; staying in Batmobile mode"
  fi
else
  # On 2.4 GHz: return only if ALL good (plus counter + cooldown)
  if (( cur_rssi >= BACK5_RSSI )) && (( cur_ping <= BACK5_PING )) && (( cur_loss <= BACK5_LOSS )) && (( cur_rate >= BACK5_RATE )); then
    good=$(inc "$STATE_GOOD"); zero "$STATE_BAD"
    batlog "🚀 5GHz return sample GOOD (#$good)"
    if (( good >= NEED_GOOD5 )) && can_switch; then
      batlog "↗️ Returning to 5GHz → ${FIVE_SSID}"
      connect_ssid "$FIVE_SSID"; exit 0
    fi
  else
    zero "$STATE_GOOD"
    batlog "🐢 2.4GHz acceptable; holding Stealth mode"
  fi
fi

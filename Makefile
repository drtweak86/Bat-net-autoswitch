# Bat-net-autoswitch Makefile
# Quick reference:
#   make install              # install scripts + systemd and copy configs to /etc/wireguard
#   make sync-configs         # re-copy config/*.conf -> /etc/wireguard with strict perms
#   make switch LOC=uk-lon    # switch to a specific profile (uk-lon, uk-man, nl-ams, de-ber, us-nyc)
#   make status               # show timer status + recent logs
#   make log                  # follow wifi-autoswitch logs
#   make enable-autopick      # enable wg-autopick.timer to choose fastest profile periodically
#   make disable-autopick     # disable wg-autopick.timer
#   make uninstall            # remove installed scripts/units (leaves /etc/wireguard/*.conf)
#   make check                # run shellcheck if available

PREFIX ?= /usr/local
SBIN          = $(PREFIX)/sbin
SYSTEMD_DIR   = /etc/systemd/system
WG_DIR        = /etc/wireguard

SCRIPTS = scripts/wg-switch scripts/wifi-autoswitch scripts/wg-autopick
UNITS   = systemd/wifi-autoswitch.service systemd/wifi-autoswitch.timer \
          systemd/wg-autopick.service systemd/wg-autopick.timer

# Default target
.PHONY: all
all: install

# --- Install everything and copy configs ---
.PHONY: install
install:
	@echo "==> Installing scripts to $(SBIN)"
	sudo install -Dm755 scripts/wg-switch         $(SBIN)/wg-switch
	sudo install -Dm755 scripts/wifi-autoswitch   $(SBIN)/wifi-autoswitch
	sudo install -Dm755 scripts/wg-autopick       $(SBIN)/wg-autopick

	@echo "==> Installing systemd units to $(SYSTEMD_DIR)"
	for u in $(UNITS); do sudo install -Dm644 $$u $(SYSTEMD_DIR)/$$(basename $$u); done
	sudo systemctl daemon-reload
	# wifi-autoswitch.timer is safe to enable immediately
	sudo systemctl enable --now wifi-autoswitch.timer || true

	@$(MAKE) --no-print-directory sync-configs

# --- Copy WireGuard configs with strict perms ---
.PHONY: sync-configs
sync-configs:
	@echo "==> Syncing WireGuard profiles to $(WG_DIR)"
	sudo install -d -m 700 $(WG_DIR)
	@if ls config/*.conf >/dev/null 2>&1; then \
	  echo "   - Copying config/*.conf -> $(WG_DIR)/"; \
	  sudo cp -f config/*.conf $(WG_DIR)/; \
	  sudo chown root:root $(WG_DIR)/*.conf; \
	  sudo chmod 600 $(WG_DIR)/*.conf; \
	else \
	  echo "   - No config/*.conf found in repo; skipping copy"; \
	fi

# --- Manual switch helper: make switch LOC=uk-lon ---
.PHONY: switch
switch:
	@if [ -z "$(LOC)" ]; then echo "Usage: make switch LOC=uk-lon"; exit 1; fi
	sudo $(SBIN)/wg-switch $(LOC)

# --- Autopick timer controls ---
.PHONY: enable-autopick disable-autopick
enable-autopick:
	sudo systemctl enable --now wg-autopick.timer
	@echo "wg-autopick.timer enabled."

disable-autopick:
	sudo systemctl disable --now wg-autopick.timer || true
	@echo "wg-autopick.timer disabled."

# --- Status & logs ---
.PHONY: status log
status:
	@echo "==> wifi-autoswitch.timer"
	systemctl status wifi-autoswitch.timer --no-pager || true
	@echo
	@echo "==> wg-autopick.timer"
	systemctl status wg-autopick.timer --no-pager || true
	@echo
	@echo "==> Last 30 lines of wifi-autoswitch.service"
	journalctl -u wifi-autoswitch.service -n 30 --no-pager || true
	@echo
	@echo "==> Last 30 lines of wg-autopick.service"
	journalctl -u wg-autopick.service -n 30 --no-pager || true

log:
	journalctl -u wifi-autoswitch.service -f

# --- Uninstall (leaves /etc/wireguard/*.conf intact) ---
.PHONY: uninstall
uninstall:
	@echo "==> Disabling timers/services"
	sudo systemctl disable --now wifi-autoswitch.timer || true
	sudo systemctl disable --now wg-autopick.timer || true
	@echo "==> Removing systemd units"
	sudo rm -f $(SYSTEMD_DIR)/wifi-autoswitch.service $(SYSTEMD_DIR)/wifi-autoswitch.timer || true
	sudo rm -f $(SYSTEMD_DIR)/wg-autopick.service   $(SYSTEMD_DIR)/wg-autopick.timer   || true
	sudo systemctl daemon-reload
	@echo "==> Removing installed scripts"
	sudo rm -f $(SBIN)/wg-switch $(SBIN)/wifi-autoswitch $(SBIN)/wg-autopick || true
	@echo "Done."

# --- Optional lint for scripts ---
.PHONY: check
check:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found; skipping"; exit 0; }
	shellcheck $(SCRIPTS)

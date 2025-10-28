# Bat-net-autoswitch Makefile (OSMC)
# Usage:
#   make install              # install scripts + systemd; copy config/*.conf
#   make sync-configs         # copy config/*.conf -> /etc/wireguard (strict perms)
#   make enable-autopick      # enable wg-autopick.timer
#   make disable-autopick     # disable wg-autopick.timer
#   make switch LOC=uk-lon    # run wg-switch <LOC>
#   make status               # show timers + recent logs
#   make uninstall            # remove installed scripts/units (keeps /etc/wireguard)
#   make check                # shellcheck scripts (if available)

PREFIX ?= /usr/local
SBIN        = $(PREFIX)/sbin
BIN         = $(PREFIX)/bin
SYSTEMD_DIR = /etc/systemd/system
WG_DIR      = /etc/wireguard

# NOTE: match your repo filenames
SCRIPTS = scripts/wg-switch scripts/wifi_autoswitch.sh scripts/wg-autopick
UNITS   = systemd/wifi-autoswitch.service systemd/wifi-autoswitch.timer \
          systemd/wg-autopick.service systemd/wg-autopick.timer

.PHONY: all install sync-configs switch status log enable-autopick disable-autopick uninstall check

all: install

install:
	@echo "==> Installing scripts"
	sudo install -Dm755 scripts/wg-switch            $(SBIN)/wg-switch
	# Keep same path/name your service already uses (seen in logs)
	sudo install -Dm755 scripts/wifi_autoswitch.sh   $(BIN)/wifi_autoswitch.sh
	# Autopick binary goes to sbin
	sudo install -Dm755 scripts/wg-autopick          $(SBIN)/wg-autopick

	@echo "==> Installing systemd units"
	for u in $(UNITS); do sudo install -Dm644 $$u $(SYSTEMD_DIR)/$$(basename $$u); done
	sudo systemctl daemon-reload
	# Your wifi-autoswitch.timer is already enabled, but this is safe:
	sudo systemctl enable --now wifi-autoswitch.timer || true

	@$(MAKE) --no-print-directory sync-configs

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

# Manual switch helper: make switch LOC=uk-lon
switch:
	@if [ -z "$(LOC)" ]; then echo "Usage: make switch LOC=uk-lon"; exit 1; fi
	sudo $(SBIN)/wg-switch $(LOC)

enable-autopick:
	sudo systemctl enable --now wg-autopick.timer
	@echo "wg-autopick.timer enabled."

disable-autopick:
	sudo systemctl disable --now wg-autopick.timer || true
	@echo "wg-autopick.timer disabled."

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

uninstall:
	@echo "==> Disabling timers/services"
	sudo systemctl disable --now wifi-autoswitch.timer || true
	sudo systemctl disable --now wg-autopick.timer || true
	@echo "==> Removing systemd units"
	sudo rm -f $(SYSTEMD_DIR)/wifi-autoswitch.service $(SYSTEMD_DIR)/wifi-autoswitch.timer || true
	sudo rm -f $(SYSTEMD_DIR)/wg-autopick.service   $(SYSTEMD_DIR)/wg-autopick.timer   || true
	sudo systemctl daemon-reload
	@echo "==> Removing installed scripts"
	sudo rm -f $(SBIN)/wg-switch $(SBIN)/wg-autopick || true
	sudo rm -f $(BIN)/wifi_autoswitch.sh || true
	@echo "Done."

check:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found; skipping"; exit 0; }
	shellcheck $(SCRIPTS)

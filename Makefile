PREFIX=/usr/local
BIN=$(PREFIX)/bin
SYSTEMD=/etc/systemd/system

INSTALL_SCRIPTS = scripts/wifi_autoswitch.sh scripts/bat-status
INSTALL_UNITS   = systemd/wifi-autoswitch.service systemd/wifi-autoswitch.timer

all:
	@echo "Targets: install, uninstall, status, run, log"

install:
	install -Dm755 scripts/wifi_autoswitch.sh $(BIN)/wifi_autoswitch.sh
	install -Dm755 scripts/bat-status        $(BIN)/bat-status
	install -Dm644 systemd/wifi-autoswitch.service $(SYSTEMD)/wifi-autoswitch.service
	install -Dm644 systemd/wifi-autoswitch.timer   $(SYSTEMD)/wifi-autoswitch.timer
	sed -i 's/\r$$//' $(BIN)/wifi_autoswitch.sh
	systemctl daemon-reload
	systemctl enable --now wifi-autoswitch.timer

uninstall:
	systemctl disable --now wifi-autoswitch.timer || true
	rm -f $(BIN)/wifi_autoswitch.sh $(BIN)/bat-status
	rm -f $(SYSTEMD)/wifi-autoswitch.service $(SYSTEMD)/wifi-autoswitch.timer
	systemctl daemon-reload

status:
	systemctl status --no-pager wifi-autoswitch.timer || true
	systemctl status --no-pager wifi-autoswitch.service || true

run:
	$(BIN)/wifi_autoswitch.sh

log:
	tail -n 50 -f /home/osmc/wifi_autoswitch.log

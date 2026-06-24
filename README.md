# RustDesk Official Updater for Debian

This script will install/update **RustDesk Desktop** and **RustDesk Server** on Linux Debian systems.

The updater downloads packages directly from the official GitHub releases:

- RustDesk Desktop: `rustdesk/rustdesk`
- RustDesk Server: `rustdesk/rustdesk-server`

The main updater script can update both Desktop and Server, but you can also create separate wrapper scripts for:

- Desktop only
- Server only

---

## Install required dependencies

```bash
sudo apt-get update
sudo apt-get install -y curl jq ca-certificates
```

---

## Create the main updater script

Create the script file:

```bash
sudo nano /usr/local/sbin/rustdesk-official-updater.sh
```

Paste the content of the `rustdesk-official-updater.sh` shell script into this file.

---

## Make the main updater executable

```bash
sudo chmod 0755 /usr/local/sbin/rustdesk-official-updater.sh
```

---

## Confirm your RustDesk Desktop installation

Check whether RustDesk Desktop is installed:

```bash
dpkg-query -W -f='${Package} ${Version}\n' rustdesk
```

Expected output should look similar to:

```text
rustdesk 1.4.8
```

You can also check the binary path:

```bash
command -v rustdesk
```

Expected output is usually:

```text
/usr/bin/rustdesk
```

---

## Confirm your RustDesk Server installation

Check that the RustDesk Server binaries are installed from the Debian packages:

```bash
command -v hbbs
command -v hbbr
command -v rustdesk-utils
```

Expected output:

```text
/usr/bin/hbbs
/usr/bin/hbbr
/usr/bin/rustdesk-utils
```

You can also check the installed Debian packages:

```bash
dpkg-query -W -f='${Package} ${Version}\n' rustdesk-server-hbbs rustdesk-server-hbbr rustdesk-server-utils
```

Expected output should look similar to:

```text
rustdesk-server-hbbs 1.1.15
rustdesk-server-hbbr 1.1.15
rustdesk-server-utils 1.1.15
```

---

# Option 1: One updater for both Desktop and Server

This service runs the main updater script and updates both RustDesk Desktop and RustDesk Server.

## Create the combined updater service

```bash
sudo tee /etc/systemd/system/rustdesk-official-updater.service >/dev/null <<'EOF'
[Unit]
Description=Update RustDesk Desktop and RustDesk Server from official GitHub releases
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rustdesk-official-updater.sh
EOF
```

## Create the combined updater timer

```bash
sudo tee /etc/systemd/system/rustdesk-official-updater.timer >/dev/null <<'EOF'
[Unit]
Description=Run RustDesk official updater every morning

[Timer]
# Change time according to your needs
OnCalendar=*-*-* 05:30:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

## Enable the combined updater

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rustdesk-official-updater.timer
```

## Check combined updater status

```bash
systemctl status rustdesk-official-updater.timer
```

## Check combined updater logs

```bash
journalctl -u rustdesk-official-updater.service -n 100 --no-pager
```

---

# Option 2: Separate Desktop-only and Server-only scripts

The main updater script supports these environment variables:

```bash
UPDATE_DESKTOP=1
UPDATE_SERVER=1
```

To make separate scripts, create small wrapper scripts.

---

## Create a Desktop-only updater script

Create the Desktop-only wrapper:

```bash
sudo tee /usr/local/sbin/rustdesk-desktop-update >/dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

UPDATE_DESKTOP=1 UPDATE_SERVER=0 exec /usr/local/sbin/rustdesk-official-updater.sh
EOF
```

Make it executable:

```bash
sudo chmod 0755 /usr/local/sbin/rustdesk-desktop-update
```

Test it manually:

```bash
sudo /usr/local/sbin/rustdesk-desktop-update
```

---

## Create a Server-only updater script

Create the Server-only wrapper:

```bash
sudo tee /usr/local/sbin/rustdesk-server-update >/dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

UPDATE_DESKTOP=0 UPDATE_SERVER=1 exec /usr/local/sbin/rustdesk-official-updater.sh
EOF
```

Make it executable:

```bash
sudo chmod 0755 /usr/local/sbin/rustdesk-server-update
```

Test it manually:

```bash
sudo /usr/local/sbin/rustdesk-server-update
```

---

# Optional: systemd service and timer for Desktop-only updates

Use this if you want RustDesk Desktop to update separately from RustDesk Server.

## Create the Desktop-only service

```bash
sudo tee /etc/systemd/system/rustdesk-desktop-update.service >/dev/null <<'EOF'
[Unit]
Description=Update RustDesk Desktop from official GitHub releases
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rustdesk-desktop-update
EOF
```

## Create the Desktop-only timer

```bash
sudo tee /etc/systemd/system/rustdesk-desktop-update.timer >/dev/null <<'EOF'
[Unit]
Description=Run RustDesk Desktop updater every morning

[Timer]
# Change time according to your needs
OnCalendar=*-*-* 05:15:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

## Enable the Desktop-only timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rustdesk-desktop-update.timer
```

## Check Desktop-only timer status

```bash
systemctl status rustdesk-desktop-update.timer
```

## Check Desktop-only updater logs

```bash
journalctl -u rustdesk-desktop-update.service -n 100 --no-pager
```

---

# Optional: systemd service and timer for Server-only updates

Use this if you want RustDesk Server to update separately from RustDesk Desktop.

## Create the Server-only service

```bash
sudo tee /etc/systemd/system/rustdesk-server-update.service >/dev/null <<'EOF'
[Unit]
Description=Update RustDesk Server from official GitHub releases
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rustdesk-server-update
EOF
```

## Create the Server-only timer

```bash
sudo tee /etc/systemd/system/rustdesk-server-update.timer >/dev/null <<'EOF'
[Unit]
Description=Run RustDesk Server updater every morning

[Timer]
# Change time according to your needs
OnCalendar=*-*-* 05:45:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

## Enable the Server-only timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rustdesk-server-update.timer
```

## Check Server-only timer status

```bash
systemctl status rustdesk-server-update.timer
```

## Check Server-only updater logs

```bash
journalctl -u rustdesk-server-update.service -n 100 --no-pager
```

---

# Important note

Use either:

1. The combined updater timer:

```text
rustdesk-official-updater.timer
```

or:

2. The separate timers:

```text
rustdesk-desktop-update.timer
rustdesk-server-update.timer
```

Do not enable both the combined timer and the separate timers unless you intentionally want multiple update checks.

---

# Disable the combined timer if using separate timers

If you decide to use the separate Desktop-only and Server-only timers, disable the combined timer:

```bash
sudo systemctl disable --now rustdesk-official-updater.timer
```

---

# Disable the separate timers if using the combined timer

If you decide to use only the combined updater, disable the separate timers:

```bash
sudo systemctl disable --now rustdesk-desktop-update.timer
sudo systemctl disable --now rustdesk-server-update.timer
```

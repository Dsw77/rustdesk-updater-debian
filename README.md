## This script will install/update Rustdesk Desktop and Rustdesk server on linux debian systems.

Create it yourself by running:  sudo nano /usr/local/sbin/rustdesk-official-updater.sh and paste the content of 
the rustdesk-official-updater shell script.


Make the file executable:
sudo chmod 0755 /usr/local/sbin/rustdesk-official-updater.sh


Confirm your server installation:

command -v hbbs
command -v hbbr
command -v rustdesk-utils


Expected output:
/usr/bin/hbbs
/usr/bin/hbbr
/usr/bin/rustdesk-utils

Create an updater service:

sudo tee /etc/systemd/system/rustdesk-official-updater.service >/dev/null <<'EOF'
[Unit]
Description=Update RustDesk and RustDesk Server from official GitHub releases
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rustdesk-official-updater.sh
EOF


##
And a timer service:

sudo tee /etc/systemd/system/rustdesk-official-updater.timer >/dev/null <<'EOF'
[Unit]
Description=Run RustDesk official updater every morning

[Timer]
##Change time according to your needs
OnCalendar=*-*-* 05:30:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

Enable the updater:
sudo systemctl daemon-reload
sudo systemctl enable --now rustdesk-official-updater.timer

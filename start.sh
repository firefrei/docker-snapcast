#!/bin/sh

# Prepare DBUS for avahi
rm -rf /var/run
mkdir -p /var/run/dbus
dbus-uuidgen --ensure
dbus-daemon --system

# Start avahi
avahi-daemon  --daemonize --no-chroot

# Start NGINX
nginx

# Start snapserver (will start shairpot-sync automatically)
snapserver -c /root/.config/snapserver/snapserver.conf

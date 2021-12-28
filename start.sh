#!/bin/sh

# Prepare DBUS for avahi
rm -rf /var/run
mkdir -p /var/run/dbus
dbus-uuidgen --ensure
dbus-daemon --system

# Start avahi
avahi-daemon  --daemonize --no-chroot

# NGINX: generate self-signed ssl certificates, if no certs are existant
if [ -s /srv/certs/snapserver.pem ] || [ -s /srv/certs/snapserver.key ] || [ -n "${SKIP_SSL_GENERATE}" ]; then
    echo "Server SSL certificates for NGINX already exist, skipping generation."
else
    echo "Generating self-signed certificates for NGINX."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /srv/certs/snapserver.pem -out /srv/certs/snapserver.key \
        -subj "/C=DE/ST=Bavaria/L=Nuremberg/O=Snapserver/CN=snapserver"
fi

# NGINX: Start
nginx

# Start snapserver (will start shairpot-sync automatically)
snapserver -c /root/.config/snapserver/snapserver.conf

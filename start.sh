#!/bin/sh
set -e

# Start dbus daemon in background
dbus-uuidgen --ensure
dbus-daemon --session --fork

# Start avahi
avahi-daemon --daemonize --no-drop-root

if [ "${NGINX_ENABLED}" -eq 1 ]; then

    # NGINX: generate self-signed ssl certificates, if no certs are existant
    if [ -s /app/certs/snapserver.pem ] || [ -s /app/certs/snapserver.key ] || [ "${NGINX_SKIP_CERT_GENERATION}" -eq 1 ]; then
        echo "Server SSL certificates for NGINX already exist, skipping generation."
    else
        echo "Generating self-signed certificates for NGINX."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /app/certs/snapserver.key -out /app/certs/snapserver.pem \
            -subj "/C=DE/ST=Bavaria/L=Nuremberg/O=Snapserver/CN=snapserver"
    fi

    # NGINX: Replace port in NGINX config
    # Note: sed cannot directly replace in-file as it cannot create a temporary file under this directory.
    sed "s/443/${NGINX_HTTPS_PORT}/g" /etc/nginx/http.d/default.conf > /tmp/default.conf
    cat /tmp/default.conf > /etc/nginx/http.d/default.conf
    rm /tmp/default.conf

    # NGINX: Start webserver
    nginx
fi

# Start snapserver (will start shairpot-sync automatically)
snapserver -c /app/config/snapserver.conf

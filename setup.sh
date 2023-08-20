#!/bin/sh
set -e

# Prepare dbus environment
dbus-uuidgen --ensure


# SNAPCAST: Create default configuration for snapserver
SNAPCAST_CONFIG=""

if [ "${PIPE_CONFIG_ENABLED}" -eq 1 ]; then
    SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = pipe://${PIPE_PATH}?name=${PIPE_SOURCE_NAME}&mode=${PIPE_MODE}\n"
fi
if [ "${AIRPLAY_CONFIG_ENABLED}" -eq 1 ]; then
    SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = airplay:///shairport-sync?name=${AIRPLAY_SOURCE_NAME}&port=5000\n"
fi
if [ "${SPOTIFY_CONFIG_ENABLED}" -eq 1 ]; then
    if [ -z "${SPOTIFY_USERNAME}" ] || [ -z "${SPOTIFY_PASSWORD}" ]; then
        echo "Error: Cannot create spotify configuration! Username and/or password are not set!"
    else
        SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = spotify:///librespot?name=${SPOTIFY_SOURCE_NAME}&username=${SPOTIFY_USERNAME}&password=${SPOTIFY_PASSWORD}&devicename=${SPOTIFY_DEVICE_NAME}&bitrate=${SPOTIFY_BITRATE}\n" /tmp/snapserver.conf
    fi
fi

# SNAPCAST: Create configuration file
cp /etc/snapserver.conf /tmp/snapserver.conf
if [ ! -z "${SNAPCAST_CONFIG}" ]; then
    # Disable default-enabled source
    sed -i 's/^source =/#source =/g' /tmp/snapserver.conf
 
    # Add user configuration to snapserver.conf
    SNAPCAST_CONFIG="# user configuration\n${SNAPCAST_CONFIG}"
    sed -i "/^\[stream\].*/a ${SNAPCAST_CONFIG}" /tmp/snapserver.conf
fi

# Copy created configuration to config directoy, if not existant yet
cp -n /tmp/snapserver.conf /app/config/snapserver.conf
rm /tmp/snapserver.conf


# Prepare NGINX configuration
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

exit 0

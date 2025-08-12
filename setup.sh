#!/bin/sh
set -e

# Prepare dbus-daemon environment
dbus-uuidgen --ensure


#
# SETUP SNAPCAST
#

# SNAPCAST: Create default configuration for snapserver
SNAPCAST_CONFIG=""

if [ "${PIPE_CONFIG_ENABLED}" -eq 1 ]; then
    SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = pipe://${PIPE_PATH}?name=${PIPE_SOURCE_NAME}&mode=${PIPE_MODE}${PIPE_EXTRA_ARGS}\n"
fi

if [ "${AIRPLAY_CONFIG_ENABLED}" -eq 1 ]; then
    if [ "${BUILD_AIRPLAY_VERSION}" -eq 2 ]; then
        AIRPLAY_PORT="7000"
        echo "[SETUP] Configuring Snapserver for Airplay 2..."
    else
        AIRPLAY_PORT="5000"
        echo "[SETUP]  Configuring Snapserver for Airplay classic/1..."
    fi

    SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = airplay:///shairport-sync?name=${AIRPLAY_SOURCE_NAME}&port=${AIRPLAY_PORT}&devicename=${AIRPLAY_DEVICE_NAME}${AIRPLAY_EXTRA_ARGS}\n"
fi

if [ "${SPOTIFY_CONFIG_ENABLED}" -eq 1 ]; then
    if [ -z "${SPOTIFY_ACCESS_TOKEN}" ]; then
        echo "[SETUP]  Warning: Spotify access token is not set! Creating config without user account. Spotify Connect client will be discoverable on the local network only."
        SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = spotify:///librespot?name=${SPOTIFY_SOURCE_NAME}&devicename=${SPOTIFY_DEVICE_NAME}&bitrate=${SPOTIFY_BITRATE}${SPOTIFY_EXTRA_ARGS}\n"
    else
        SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = spotify:///librespot?name=${SPOTIFY_SOURCE_NAME}&access-token=${SPOTIFY_ACCESS_TOKEN}&devicename=${SPOTIFY_DEVICE_NAME}&bitrate=${SPOTIFY_BITRATE}${SPOTIFY_EXTRA_ARGS}\n"
    fi
fi

if [ "${META_CONFIG_ENABLED}" -eq 1 ]; then
    if [ -z "${META_SOURCES}" ]; then
        echo "[SETUP]  Error: Cannot create meta configuration! Sources are not set!"
    else
        SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = meta:///${META_SOURCES}?name=${META_SOURCE_NAME}${META_EXTRA_ARGS}\n"
    fi
fi

if [ ! -z "${SOURCE_CUSTOM}" ]; then
    SNAPCAST_CONFIG="${SNAPCAST_CONFIG}source = ${SOURCE_CUSTOM}\n"
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


#
# SETUP HTTPS
#
if [ "${HTTPS_ENABLED}" -eq 1 ]; then
    # Generate CA and certificates
    if [ "${SKIP_CERT_GENERATION}" -eq 0 ]; then
        /bin/bash /app/gen-certs.sh
    fi

    # Enable HTTPS in configuration
    sed -i 's|^#\?ssl_enabled =.*|ssl_enabled = true|' /tmp/snapserver.conf
    sed -i 's|^#\?certificate =.*|certificate = /app/certs/snapserver.crt|' /tmp/snapserver.conf
    sed -i 's|^#\?certificate_key =.*|certificate_key = /app/certs/snapserver.key|' /tmp/snapserver.conf
fi

# Copy created configuration to config directoy, if not existant yet
cp -n /tmp/snapserver.conf /app/config/snapserver.conf
rm /tmp/snapserver.conf



#
# SETUP SHAIRPORT-SYNC
#

# Prepare Shairport-Sync Airplay-2 configuration
if [ "${BUILD_AIRPLAY_VERSION}" -eq 2 ]; then
    NQPTP_SUPERVISORD_CONFIG="
    [program:nqptp]\n
    command=/usr/local/bin/nqptp\n
    autostart=true\n
    autorestart=true\n
    startsecs=3\n
    startretries=5\n
    priority=21\n
    "
    echo -e "${NQPTP_SUPERVISORD_CONFIG}" > /app/supervisord/nqptp.ini
fi

exit 0

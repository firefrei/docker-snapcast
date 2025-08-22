FROM alpine:edge AS snapcast

ARG UID=1000
ARG GID=1000

# manually add user to map ids to host's file system
RUN addgroup -g "${GID}" -S snapcast
RUN adduser -u "${UID}" -D -G snapcast -h '/var/lib/snapserver' -H snapcast

# Install snapcast-server and snapweb
RUN apk add --no-cache --upgrade snapcast-server \
  # Install latest release of snapweb 
  # (its not shipped with snapcast-server, and not shipped with snapcast since 0.28.0 anymore)
  && wget -O /tmp/snapweb.zip https://github.com/badaix/snapweb/releases/latest/download/snapweb.zip \
  && unzip -o /tmp/snapweb.zip -d /usr/share/snapserver/snapweb/ \
  && rm /tmp/snapweb.zip \
  # Install dependencies for snapserver metadata scripts
  # (located in https://github.com/badaix/snapcast/blob/develop/server/etc/plug-ins/meta_mopidy.py and meta_mpd.py)
  && apk add --no-cache --upgrade py3-websocket-client py3-mpd2 py3-musicbrainzngs py3-gobject3 py3-dbus py3-requests

# Expose Ports
## Snapcast Ports: 1704-1705 1780 1788
EXPOSE 1704-1705 1780 1788

ENTRYPOINT [ "/usr/bin/snapserver" ]


###
# Airplay with Shairport-Sync
# - install shairport-sync runtime dependencies
# - build shairport sync
FROM snapcast AS snapcast-airport
ARG AIRPLAY_VERSION
ENV BUILD_AIRPLAY_VERSION="${AIRPLAY_VERSION:-1}"

RUN apk add --no-cache dbus popt openssl soxr avahi libconfig glib \
  && apk add --no-cache --upgrade --virtual .build-deps git build-base autoconf automake libtool popt-dev openssl-dev soxr-dev avahi-dev libconfig-dev glib-dev \
  && mkdir -p /app/build \
  && CONF_OPTIONS="\
      --with-stdout \
      --with-dbus-interface \
      --with-avahi \
      --with-ssl=openssl \
      --with-soxr \
      --with-metadata" \
  #
  # Airplay-2 support: If enabled, add and build its dependencies
  && if [ "${BUILD_AIRPLAY_VERSION}" -eq 2 ]; then \
    CONF_OPTIONS="${CONF_OPTIONS} --with-airplay-2" \
    && apk add --no-cache --upgrade ffmpeg libplist libsodium libgcrypt libuuid \
    && apk add --no-cache --upgrade --virtual .build-deps-airplay2 ffmpeg-dev libplist-dev libsodium-dev libgcrypt-dev xxd \
    && cd /app/build \
    && git clone https://github.com/mikebrady/nqptp.git nqptp.git \
    && cd nqptp.git \
    && autoreconf -fi \
    && ./configure \
    && make \
    && make install \
  ; fi \
  #
  # Build shairport-sync with metadata, stdout and pipe support (apk repo is without)
  && cd /app/build \
  && git clone https://github.com/mikebrady/shairport-sync.git shairport-sync.git \
  && cd shairport-sync.git \
  && autoreconf -i -f \
  && ./configure ${CONF_OPTIONS} \
  && make \
  && make install \
  #
  # Cleanup build environment
  && apk del --purge .build-deps \
  && if [ "${BUILD_AIRPLAY_VERSION}" -eq 2 ]; then apk del --purge .build-deps-airplay2; fi \
  && rm -rf /app/build \
  #
  # Configure dbus-daemon and avahi-daemon for rootless execution
  # Ref: https://gnaneshkunal.github.io/avahi-docker-non-root.html
  && echo "<busconfig><listen>unix:path=/var/run/dbus/system_bus_socket</listen></busconfig>" > /usr/share/dbus-1/session.d/custom.conf \
  && mkdir -p /var/run/dbus \
  && chmod 777 /var/run/dbus/ \
  && chmod 777 /etc/avahi/avahi-daemon.conf \
  && mkdir -p /var/run/avahi-daemon \
  && chown avahi:avahi /var/run/avahi-daemon \
  && chmod 777 /var/run/avahi-daemon


###
# Build and install librespot (Spotify Client)
# - Disable all audio out plugins, as they are not needed.
FROM snapcast-airport AS snapcast-airport-spotify
RUN mkdir -p /app/build \
  && cd /app/build \
  && apk add --no-cache --upgrade --virtual .build-deps git libconfig-dev cargo build-base cmake rust-bindgen clang18-dev \
  && git clone -b dev https://github.com/librespot-org/librespot.git librespot.git \
  && cd librespot.git \
  && cargo build --release --no-default-features --features with-avahi \
  && cp ./target/release/librespot /usr/sbin/ \
  && chmod +x /usr/sbin/librespot \
  #
  # Cleanup build environment
  && cargo clean \
  && apk del --purge .build-deps \
  && rm -rf /app/build ~/.cargo


###
# Create final image
FROM snapcast-airport-spotify AS snapcast-extended

ENV TZ="Etc/UTC"

ENV PIPE_CONFIG_ENABLED="0"
ENV PIPE_SOURCE_NAME="Pipe"
ENV PIPE_PATH="/tmp/snapfifo"
ENV PIPE_MODE="create"
ENV PIPE_EXTRA_ARGS=""

ENV AIRPLAY_CONFIG_ENABLED="1"
ENV AIRPLAY_SOURCE_NAME="Airplay"
ENV AIRPLAY_DEVICE_NAME="Snapcast"
ENV AIRPLAY_EXTRA_ARGS=""

ENV SPOTIFY_CONFIG_ENABLED="0"
ENV SPOTIFY_SOURCE_NAME="Spotify"
ENV SPOTIFY_ACCESS_TOKEN=""
ENV SPOTIFY_DEVICE_NAME="Snapcast"
ENV SPOTIFY_BITRATE="320"
ENV SPOTIFY_EXTRA_ARGS=""

ENV META_CONFIG_ENABLED="0"
ENV META_SOURCE_NAME="Mix"
ENV META_SOURCES=""
ENV META_EXTRA_ARGS=""

ENV SOURCE_CUSTOM=""

ENV HTTPS_ENABLED="1"
ENV SKIP_CERT_GENERATION="0"
ENV CERT_SERVER_CN="snapserver"
ENV CERT_SERVER_DNS="snapserver snapserver.local"


# Install steps
# - install and configure supervisord
# - copy runtime scripts
RUN apk add --no-cache --upgrade supervisor tzdata curl bash \
  && mkdir -p /app/config /app/data /app/certs/ \
  #
  # Create configuration and environment for supervisord
  && mkdir -p /app/supervisord /run/supervisord /var/log/supervisord \
  && cp /etc/supervisord.conf /app/supervisord/supervisord.conf \
  && sed -i 's/^files =.*/files = \/app\/supervisord\/*.ini/g' /app/supervisord/supervisord.conf \
  && sed -i 's/\/run\/supervisord.sock/\/run\/supervisord\/supervisord.sock/g' /app/supervisord/supervisord.conf \
  && chown -R snapcast:snapcast /run/supervisord /app/supervisord /var/log/supervisord \
  #
  # Configure app directory owner
  && chown -R snapcast:snapcast /app

# Add supervisord configuration
ADD --chown=snapcast:snapcast config/supervisord/supervisord.ini /app/supervisord/snapcast.ini

# Copy setup and healtcheck script
ADD --chown=snapcast:snapcast --chmod=0775 setup.sh gen-certs.sh healthcheck.sh /app/

USER snapcast:snapcast
WORKDIR /app
VOLUME [ "/app/config", "/app/data", "/app/certs" ]

HEALTHCHECK CMD [ "/bin/sh", "/app/healthcheck.sh" ]

# Expose Ports
## Snapcast Ports:   1704-1705 1780 1788
## Shairport-Sync:
### Ref: https://github.com/mikebrady/shairport-sync/blob/master/TROUBLESHOOTING.md#ufw-firewall-blocking-ports-commonly-includes-raspberry-pi
### AirPlay ports:    3689/tcp 5000/tcp 6000-6009/udp
### AirPlay-2 ports:  3689/tcp 5000/tcp 6000-6009/udp 7000/tcp for airplay, 319-320/udp for NQPTP
### Avahi ports:      5353
EXPOSE 1704-1705 1780 1788 3689 5000 6000-6009/udp 7000 319-320/udp 5353

# Run start script
ENTRYPOINT [ "/bin/sh", "-c" ]
CMD [ "/app/setup.sh && /usr/bin/supervisord -c /app/supervisord/supervisord.conf" ]

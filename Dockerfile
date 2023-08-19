FROM alpine:edge AS snapcast

# Install snapcast
# Note: Do not install snapcast-server (does not include webdir, ...), install snapcast instead
RUN apk add --no-cache --upgrade snapcast

# Expose Ports
## Snapcast Ports: 1704-1705 1780
EXPOSE 1704-1705 1780

ENTRYPOINT [ "/usr/bin/snapserver" ]


###
FROM snapcast AS snapcast-extended

ENV NGINX_SKIP_CERT_GENERATION "0"
ENV NGINX_HTTPS_PORT "443"

# Install and build steps
# - install shairport-sync runtime dependencies
# - build shairport sync
# - build librespot
# - install nginx
RUN apk add --no-cache dbus alsa-lib libdaemon popt openssl soxr avahi libconfig glib supervisor curl \
  && mkdir -p /app/build /app/config /app/data \
  #
  # Build shairport-sync with metadata, stdout and pipe support (apk repo is without)
  && apk add --no-cache --upgrade --virtual .build-deps-shairport git build-base autoconf automake libtool alsa-lib-dev libdaemon-dev popt-dev openssl-dev soxr-dev avahi-dev libconfig-dev glib-dev \
  && cd /app/build \
  && git clone https://github.com/mikebrady/shairport-sync.git shairport-sync.git \
  && cd shairport-sync.git \
  && autoreconf -i -f \
  && ./configure \
        --with-alsa \
        --with-pipe \
        --with-stdout \
        --with-dbus-interface \
        --with-avahi \
        --with-ssl=openssl \
        --with-soxr \
        --with-metadata \
  && make \
  && make install \
  #
  # Configure dbus-daemon and avahi-daemon for rootless execution
  # Ref: https://gnaneshkunal.github.io/avahi-docker-non-root.html
  && echo "<busconfig><listen>unix:path=/var/run/dbus/system_bus_socket</listen></busconfig>" > /usr/share/dbus-1/session.d/custom.conf \
  && mkdir -p /var/run/dbus \
  && chmod 777 /var/run/dbus/ \
  && chmod 777 /etc/avahi/avahi-daemon.conf \
  && mkdir -p /var/run/avahi-daemon \
  && chown avahi:avahi /var/run/avahi-daemon \
  && chmod 777 /var/run/avahi-daemon \
  #
  # Build and install librespot (Spotify Client)
  # - Disable all audio out plugins, as they are not needed.
  && cd /app/build \
  && git clone https://github.com/librespot-org/librespot librespot.git \
  && cd librespot.git \
  && apk add --no-cache --upgrade --virtual .build-deps-librespot libconfig-dev cargo build-base \
  && cargo build --release --no-default-features \
  && cp ./target/release/librespot /usr/sbin/ \
  && chmod +x /usr/sbin/librespot \
  #
  # Cleanup
  && cargo clean \
  && apk del --purge .build-deps-shairport .build-deps-librespot \
  && rm -rf /app/build ~/.cargo \
  #
  # Install NGINX for SSL reverse proxy to webinterface
  && apk add --no-cache --upgrade nginx \
  && mkdir -p /run/nginx/ /app/certs/ \
  && chown -R snapcast:snapcast /var/lib/nginx /var/log /usr/lib/nginx /run/nginx \
  #
  # Create default configuration for snapserver
  && cp /etc/snapserver.conf /app/config/snapserver.conf \
  && sed -i '/^#source =.*/a source = airplay:///shairport-sync?name=Snapcast&port=5000' /app/config/snapserver.conf \
  #
  # Configure app directory owner
  && chown -R snapcast:snapcast /app

# Add supervisord configuration
ADD --chown=snapcast:snapcast config/supervisord/supervisord.ini /app/supervisor.d/snapcast.ini

# Add NGINX configuration
ADD --chown=snapcast:snapcast config/nginx/default.conf /etc/nginx/http.d/default.conf

# Copy setup and healtcheck script
ADD --chown=snapcast:snapcast --chmod=0775 setup.sh /app/setup.sh
ADD --chown=snapcast:snapcast --chmod=0775 healthcheck.sh /app/healthcheck.sh

USER snapcast:snapcast
WORKDIR /app
VOLUME [ "/app/config", "/app/data", "/app/certs" ]

HEALTHCHECK CMD [ "/bin/sh", "/app/healthcheck.sh" ]

# Expose Ports
## Snapcast Ports: 1704-1705 1780
## AirPlay ports:  3689/tcp 5000-5005/tcp 6000-6005/udp
## Avahi ports:    5353
## NGINX ports:    443 or user defined
EXPOSE 1704-1705 1780 3689 5000-5005 6000-6005/udp 5353 "${NGINX_HTTPS_PORT}"

# Run start script
ENTRYPOINT [ "/bin/sh", "-c" ]
CMD [ "/app/setup.sh && /usr/bin/supervisord -c /app/supervisor.d/snapcast.ini" ]

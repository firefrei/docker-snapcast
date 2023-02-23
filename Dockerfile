FROM alpine:edge AS snapcast

# Install snapcast
# Note: Do not install snapcast-server (does not include webdir, ...), install snapcast instead
RUN apk add --no-cache --upgrade snapcast

ENTRYPOINT [ "/usr/bin/snapserver" ]


###
FROM snapcast AS snapcast-extended

# Install and build steps
# - install shairport-sync runtime dependencies
# - build shairport sync
# - build librespot
# - install nginx
RUN apk add --no-cache dbus alsa-lib libdaemon popt openssl soxr avahi libconfig \
  #
  # Note: Build shairport-sync with metadata, stdout and pipe support (apk repo is without)
  && apk add --no-cache --upgrade --virtual .build-deps-shairport git build-base autoconf automake libtool alsa-lib-dev libdaemon-dev popt-dev libressl-dev soxr-dev avahi-dev libconfig-dev \
  && mkdir -p /app/build \
  && cd /app/build \
  && git clone https://github.com/mikebrady/shairport-sync.git shairport-sync.git \
  && cd shairport-sync.git \
  && autoreconf -i -f \
  && ./configure \
        --with-alsa \
        --with-pipe \
        --with-stdout \
        --with-avahi \
        --with-ssl=openssl \
        --with-soxr \
        --with-metadata \
  && make \
  && make install \
  && apk del --purge .build-deps \
  #
  # Build and Install librespot (Spotify Client)
  # - Disable all audio out plugins, as they are not needed.
  && cd /app/build \
  && git clone https://github.com/librespot-org/librespot librespot \
  && cd librespot.git \
  && apk add --no-cache --upgrade --virtual .build-deps-librespot libconfig-dev cargo build-essential \
  && cargo build --release --no-default-features \
  && cp ./target/release/librespot /usr/sbin/ \
  && chmod +x /usr/sbin/librespot \
  # Cleanup
  && apk del --purge .build-deps-shairport .build-deps-librespot \
  && rm -rf /app/build \
  #
  # Install NGINX for SSL reverse proxy to webinterface
  && apk add --no-cache --upgrade nginx


# Install NGINX for SSL reverse proxy to webinterface
RUN mkdir -p /run/nginx/ /app/certs/
COPY nginx.conf/default.conf /etc/nginx/http.d/default.conf
VOLUME /app/certs



# Copy startup script
WORKDIR /app
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Expose Ports
## Snapcast Ports: 1704-1705 1780
## AirPlay ports:  3689/tcp 5000-5005/tcp 6000-6005/udp
## Avahi ports:    5353
## NGINX ports:    443
EXPOSE 1704-1705 1780 3689 5000-5005 6000-6005/udp 5353 443

# Run start script
ENV PATH "/root/.cargo/bin:$PATH"
CMD ["/app/start.sh"]

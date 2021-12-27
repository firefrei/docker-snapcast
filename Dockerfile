# Dockerfile for a Multi-Room-Audio-Streaming-Server
FROM alpine:latest

# Build shairport-sync with metadata, stdout and pipe support (apk repo is without)
# RUN apk add shairport-sync --update --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing
RUN apk add git build-base autoconf automake libtool alsa-lib-dev libdaemon-dev popt-dev libressl-dev soxr-dev avahi-dev libconfig-dev
RUN cd /root \
 && git clone https://github.com/mikebrady/shairport-sync.git \
 && cd shairport-sync \
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
 && cd /

# Install Shairport Runtime dependencies
RUN apk add dbus alsa-lib libdaemon popt libressl soxr avahi libconfig

# Install snapcast
# Note: Do not install snapcast-server (does not include webdir, ...), install snapcast instead
RUN apk add snapcast --update --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community

# Install librespot (Spotify Client)
RUN apk add cargo
RUN cargo install librespot
#RUN git clone https://github.com/librespot-org/librespot /tmp/librespot.git
#RUN cd /tmp/librespot.git \
#  && cargo build --release \
#  && cp target/release/librespot /usr/local/bin/ \
#  && cargo clean \
#  && cd /
#RUN rm -rf /tmp/librespot.git

# Install NGINX for SSL reverse proxy to webinterface
RUN mkdir /run/nginx/
RUN apk add nginx

# Cleanup
RUN apk --purge del git build-base autoconf automake libtool alsa-lib-dev libdaemon-dev popt-dev libressl-dev soxr-dev avahi-dev libconfig-dev cargo
RUN rm -rf \
        /etc/ssl \
        /var/cache/apk/* \
        /lib/apk/db/* \
        /root/shairport-sync

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Snapcast Ports
EXPOSE 1704-1705
EXPOSE 1780

# AirPlay ports.
EXPOSE 3689/tcp
EXPOSE 5000-5005/tcp
EXPOSE 6000-6005/udp

# Avahi port
EXPOSE 5353

# NGINX port
EXPOSE 443 

# Run startscript
ENV PATH "/root/.cargo/bin:$PATH"
CMD ["./start.sh"]

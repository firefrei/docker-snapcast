FROM alpine:latest

# Add edge and testing as tagged repositories to APK (will only be used when tag is explicitly named)
RUN echo -e "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main\n@edgecommunity https://dl-cdn.alpinelinux.org/alpine/edge/community\n@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
  && apk update

# Install shairport-sync Runtime dependencies
RUN apk add --no-cache dbus alsa-lib libdaemon popt libressl soxr avahi libconfig 

# Note: Build shairport-sync with metadata, stdout and pipe support (apk repo is without)
#   APK way: `RUN apk add shairport-sync --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing`
RUN apk add --no-cache git build-base autoconf automake libtool alsa-lib-dev libdaemon-dev popt-dev libressl-dev soxr-dev avahi-dev libconfig-dev \
  && mkdir -p /srv/build \
  && cd /srv/build \
  && git clone https://github.com/mikebrady/shairport-sync.git shairport-sync \
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
  && cd / \
  && apk del --purge git build-base autoconf automake libtool alsa-lib-dev libdaemon-dev popt-dev libressl-dev soxr-dev avahi-dev libconfig-dev


# Install snapcast
# Note: Do not install snapcast-server (does not include webdir, ...), install snapcast instead
# FixMe: Added libstdc++ from edge to meet newest snapcast dependencies. Can be removed, if main libstdc++ is updated (10.3.1_git20211027-r0 -> 11.2.1_git20211128-r3) [2021-12-28]
RUN apk add --no-cache libstdc++@edge snapcast@edgecommunity

# Install librespot (Spotify Client)
RUN apk add --no-cache libconfig-dev alsa-lib-dev cargo \
  && cargo install librespot \
  && apk del --purge libconfig-dev alsa-lib-dev cargo

# Install NGINX for SSL reverse proxy to webinterface
RUN mkdir -p /run/nginx/ /srv/certs/ \
  && apk add --no-cache nginx openssl
COPY nginx.conf/default.conf /etc/nginx/http.d/default.conf
VOLUME /srv/certs

# Cleanup
RUN rm -rf \
  /srv/build

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh


# Expose Ports
## Snapcast Ports
EXPOSE 1704-1705 1780
## AirPlay ports
EXPOSE 3689/tcp 5000-5005/tcp 6000-6005/udp
## Avahi ports
EXPOSE 5353
## NGINX ports
EXPOSE 443 


# Run start script
ENV PATH "/root/.cargo/bin:$PATH"
CMD ["./start.sh"]

# Snapcast container image for Docker 
### In a nutshell
[Snapcast](https://github.com/badaix/snapcast) multi-room-audio-streaming with AirPlay, Spotify and HTTPS support enabled. Based on Alpine Linux.

### Long version
This docker image serves a [Snapcast server](https://github.com/badaix/snapcast) together with AirPlay (via [shairport-sync](https://github.com/mikebrady/shairport-sync)) and Spotify (via [librespot](https://github.com/librespot-org/librespot)).
Snapcast is loaded from the edge branch of alpines repositories while shairport-sync and librespot are built manually with recommended options by Snapcast.  
Additionally, NGINX is installed in the image to provide a HTTPS-secured connection to the Snapweb UI (HTTP-only is directly provided by Snapcast).


## Usage

### Docker Compose (recommended)
See [docker-compose.yaml](docker-compose.yaml) for an example configuration.

### Docker CLI
Run container with:
```bash
docker run -it \
  -p '1704-1705:1704-1705' \
  -p '1780:1780' \
  -p '3689:3689' \
  -p '5000-5005:5000-5005' \
  -p '6000-6005:6000-6005/udp' \
  -p '5353:5353' \
  -p '443:443' \
  -v '/etc/localtime:/etc/localtime:ro' \
  -v '~/config_snapcast/:/root/.config/snapserver/'
  firefrei/snapcast
```

Optional volume mounts for NGINX reverse proxy:
```bash
  -v ~/nginx_certs/:/srv/certs/
```

### HTTPS-secured connection to Snapweb
NGINX is configured as a reverse proxy and will listen on port 443. The folder `/srv/certs/` must contain the TLS certificate files: `snapserver.pem` contains the certificate (chain) and `snapserver.key` the private key file.


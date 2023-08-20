# Snapcast Server Container

Source on GitHub: [https://github.com/firefrei/docker-snapcast](https://github.com/firefrei/docker-snapcast)  
Image on Docker Hub: [https://hub.docker.com/r/firefrei/snapcast](https://hub.docker.com/r/firefrei/snapcast)  

### In a Nutshell
[Snapcast](https://github.com/badaix/snapcast) multi-room audio-streaming with AirPlay, Spotify and HTTPS support built-in. Based on Alpine Linux.

### Long Version
This docker image serves...
- [Snapcast](https://github.com/badaix/snapcast) server
- AirPlay Classic/1 (via [shairport-sync](https://github.com/mikebrady/shairport-sync) with dbus-and avahi-daemon) as snapcast source
- AirPlay 2 support (see docker image tags with suffix `-airplay2`)
- Spotify (via [librespot](https://github.com/librespot-org/librespot)) as snapcast source
- NGINX to provide a HTTPS-secured connection to the Snapweb UI (HTTP-only is directly provided by Snapcast) [optional]
- Configuration generator based on environment variables [optional]
- Supervisord to manage and observe all processes in the container
- A root-less container environment based on Alpine Linux

Snapcast is loaded from the edge branch of Alpines APK repositories while `shairport-sync` and `librespot` are built manually with recommended options by Snapcast. 

Some services may require to bind privileged port numbers (<1024). Check [Network Tweaks](#network-tweaks) section below.

Please note when using Airplay Classic/1: To broadcast the airplay speaker announcements to all iOS devices, `avahi-daemon` is required and used by shairport-sync. As broadcasts can only work in a layer-2 network domain, the container needs to be attached to the same layer-2 network as the clients (see [docker-compose.yaml](docker-compose.yaml) for an example). As a consequence, in routed layer-3 setups (e.g., Kubernetes), Airplay cannot function out of the box. You may try to workaround this issue by using an MDNS repeater, however, this is not tested and not supported.  

Please note when using Airplay-2: In addition to the requirements for AirPlay Classic/1, Airplay-2 requires NQPTP which needs to bind privileged ports. Check [Network Tweaks](#network-tweaks) section below.


## Container Usage
### Configuration
You can either provider your own `snapserver.conf` file to the snapcast server or you let it generate automatically on startup. Use the environment variables mentioned below to control the config file generation.

### Environment Variables
Pipe:
- `PIPE_CONFIG_ENABLED`: Enable the generation of a Snapcast `source` for reading from a FIFO pipe in the snapserver configuration file on container startup. Set to `1` to enable, defaults to `0`.
- `PIPE_SOURCE_NAME`: Source name of the FIFO pipe input in Snapcast. Defaults to `Pipe`.
- `PIPE_PATH`: Path to the FIFO pipe or where it should be created. Defaults to `/tmp/snapfifo`.
- `PIPE_MODE`: Set to `create` to create a FIFO pipe, if it does not exist. Else set to `read`. Defaults to `create`.
- `PIPE_EXTRA_ARGS`: (advanced) Add additional arguments to `source` configuration. Format: `&key=value`.

AirPlay:
- `AIRPLAY_CONFIG_ENABLED`: Enable the generation of a Snapcast `source` for AirPlay in the snapserver configuration file on container startup. Set to `0` to disable, defaults to `1`.
- `AIRPLAY_SOURCE_NAME`: Source name of Airplay in Snapcast. Defaults to `Airplay`.
- `AIRPLAY_EXTRA_ARGS`: (advanced) Add additional arguments to `source` configuration. Format: `&key=value`.

Spotify:
- `SPOTIFY_CONFIG_ENABLED`: Enable the generation of a Snapcast `source` for AirPlay in the snapserver configuration file on container startup. Set to `1` to enable, defaults to `0`.
- `SPOTIFY_SOURCE_NAME`: Source name of Spotify in Snapcast. Defaults to `Spotify`.
- `SPOTIFY_USERNAME`: (required) Username to login at Spotify API. Defaults to empty string.
- `SPOTIFY_PASSWORD`: (required) Password to login at Spotify API. Defaults to empty string. Attention: The password is stored in clear-text format in the configuration file!
- `SPOTIFY_DEVICE_NAME`: Speaker name in Spotify app. Defaults to `Snapcast`.
- `SPOTIFY_BITRATE`: Bitrate to stream from Spotify. Defaults to `320` for high quality.
- `SPOTIFY_EXTRA_ARGS`: (advanced) Add additional arguments to `source` configuration. Format: `&key=value`.

Meta:
- `META_CONFIG_ENABLED`: Enable the generation of a Snapcast `source` for meta stream mix in the snapserver configuration file on container startup. Set to `1` to enable, defaults to `0`.
- `META_SOURCE_NAME`: Source name of Spotify in Snapcast. Defaults to `Mix`.
- `META_SOURCES`: (required) List of sources to include in the mix. Source #1 has the highest priority. Defaults to empty string.
- `META_EXTRA_ARGS`: (advanced) Add additional arguments to `source` configuration. Format: `&key=value`.

Custom:
- `SOURCE_CUSTOM`: (advanced) Additional custom source to add to the Snapcast `source` configuration. Defaults to empty string. Format example: `file:///<path/to/PCM/file>?name=<name>`.

NGINX:
- `NGINX_ENABLED`: Set to `1` to enable NGINX reverse proxy for serving HTTPS. Defaults to `0`.
- `NGINX_SKIP_CERT_GENERATION`: Set to `1` to disable certificate generation on startup (if not existant). Defaults to `0`.
- `NGINX_HTTPS_PORT`: HTTPS port NGINX will bind to. Defaults to `443`, which will only work if docker can bind this port. If having trouble, try a port number above 1024 or adjust the privileges of the container.

General:
- `TZ`: Your system time zone (for logging, etc.). Defaults to `Etc/UTC`.


### Volume Mounts
- `/app/config/`  
  Path to snapcast server configuration. Place your custom `snapserver.conf` file here. Snapserver is going to load `/app/config/snapserver.conf` as its main configuration file.
  If volume is not mounted or the file does not exist, the startup script is going to create a default configuration file. See the environment variables section to control the generation.
- `/app/data/`  
  Snapserver is going to place its run-time configuration (like `server.json`) here.
- `/app/certs/`  
  NGINX is configured as a reverse proxy to serve a HTTPS-secured connection to Snapweb. This folder must contain the TLS certificate files: `snapserver.pem` contains the certificate (chain) and `snapserver.key` the private key file.
  If volume is not mounted or the mentioned files do not exist, self-signed certificates are created and stored under this location.


## Container Setup
### Docker Compose (recommended)
See [docker-compose.yaml](docker-compose.yaml) for an example configuration.

### Docker CLI
Run container with:
```bash
docker run \
  -p '1704-1705:1704-1705' \
  -p '1780:1780' \
  -p '3689:3689' \
  -p '5000:5000' \
  -p '6000-6009:6000-6009/udp' \
  -p '5353:5353' \
  -p '443:443' \
  [-p '7000:7000'] \
  [-p '319-320:319-320/udp'] \
  [-v <your-volume-mounts>] \
  [-e <your-environment-variables>] \
  firefrei/snapcast
```

### Network Tweaks
Binding ports numbers below 1024 requires root privileges under linux. As the container runs without root privileges, you need to grant the binding, if required:
- Airplay-2 requires NQPTP, which binds the ports `319/udp` and `320/udp`
- NGINX is (per default) configured to bind to HTTPS port `443/tcp`. This port can also be changed to another number.

Depending on your system and the security you require, you can allow binding to privileged ports by adding the `NET_BIND_SERVICE` linux capability to the container:
```bash
docker run ... --cap-add=NET_BIND_SERVICE ...
```

If the docker daemon itself is not allowed to bind privileged ports, you may also allow the binding system-wide.
Grant the privilege for **all** processes(!):
```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
```
Please note that this may affect the security of your complete system.

#!/bin/sh
set -o pipefail

SNAPSERVER_API_PORT="1780"

# Retrieve snapserver status
API_RESPONSE=$(curl --silent --user-agent healthcheck -X POST -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' http://localhost:${SNAPSERVER_API_PORT}/jsonrpc)

# Check snapserver
echo "${API_RESPONSE}" | grep -q "snapserver" || exit 1
echo "snapserver is running..."

# Check airplay
echo "${API_RESPONSE}" | grep -q "airplay"
AIRPLAY_NOT_ENABLED=$?

if [ "${AIRPLAY_NOT_ENABLED}" -eq 0 ]; then
    RES=$(pgrep -n shairport-sync || exit 2)
    echo "shairport-sync is running..."

    RES=$(pgrep -n avahi-daemon || exit 3)
    echo "avahi-daemon is running..."

    RES=$(pgrep -n dbus-daemon || exit 4)
    echo "dbus-daemon is running..."
fi

# Check nginx
if [ "${NGINX_ENABLED}" -eq 1 ]; then
    RES=$(pgrep -n nginx || exit 5)
    echo "nginx is running..."
fi

exit 0

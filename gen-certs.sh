#!/usr/bin/env bash
set -euo pipefail

# ======= CONFIGURTION =======
OUT_DIR="/app/certs"

# Server
SERVER_CN="$CERT_SERVER_CN"
SERVER_DNS=("$CERT_SERVER_DNS")

# Client (mTLS)
CLIENT_CN="snapclient"

# Expiry Dates
CA_DAYS=3650
SERVER_DAYS=825
CLIENT_DAYS=365

# Distinguished Names
C="DE"; ST="Bavaria"; L="Nuremberg"
ORG_CA="Snap-CA"; ORG_SERVER="Snapserver"; ORG_CLIENT="Snapclient"

# ======= GENERATION =======
mkdir -p "$OUT_DIR"
trap 'rm -f "$OUT_DIR"/.tmp-*.cnf "$OUT_DIR"/.srl 2>/dev/null || true' EXIT

# Helpers
join_by() { local IFS="$1"; shift; echo "$*"; }
mk_subject() { # $1=O, $2=CN
  printf "/C=%s/ST=%s/L=%s/O=%s/CN=%s" "$C" "$ST" "$L" "$1" "$2"
}
mk_san() {
  local parts=()
  read -r -a dns_array <<< "$SERVER_DNS"
  for d in "${dns_array[@]}"; do parts+=("DNS:${d}"); done
  join_by , "${parts[@]}"
}

# 1) CA (EC P-256)
CA_KEY="$OUT_DIR/snapca.key"
CA_CRT="$OUT_DIR/snapca.crt"
if [[ ! -s "$CA_KEY" || ! -s "$CA_CRT" ]]; then
  echo ">> Creating CA..."
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$CA_KEY"
  openssl req -x509 -new -sha256 -days "$CA_DAYS" \
    -key "$CA_KEY" -out "$CA_CRT" \
    -subj "$(mk_subject "$ORG_CA" 'Snapserver Root CA')"
else
  echo ">> CA is already existing, skipping."
fi

# 2) Server-Key + CSR + Cert
SERVER_KEY="$OUT_DIR/snapserver.key"
SERVER_CSR="$OUT_DIR/snapserver.csr"
SERVER_CRT="$OUT_DIR/snapserver.crt"
SERVER_CFG="$OUT_DIR/.tmp-server.cnf"

if [ ! -s "$SERVER_CRT" ]; then
    echo ">> Creating Server-Certificate..."

    SAN_VAL="$(mk_san)"
    [[ -z "$SAN_VAL" ]] && { echo "ERROR: No SANs defined (SERVER_DNS)"; exit 1; }

    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$SERVER_KEY"

cat >"$SERVER_CFG" <<EOF
[ req ]
default_md = sha256
prompt = no
distinguished_name = dn
req_extensions = req_ext

[ dn ]
C = $C
ST = $ST
L = $L
O = $ORG_SERVER
CN = $SERVER_CN

[ req_ext ]
subjectAltName = $SAN_VAL
keyUsage = digitalSignature
extendedKeyUsage = serverAuth

[ x509_ext ]
subjectAltName = $SAN_VAL
keyUsage = digitalSignature
extendedKeyUsage = serverAuth
EOF

    openssl req -new -sha256 -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$SERVER_CFG"
    openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$SERVER_CRT" -days "$SERVER_DAYS" -sha256 \
    -extfile "$SERVER_CFG" -extensions x509_ext

else
    echo ">> Server-Certificate is already existing, skipping."
fi


# 3) Client-Key + CSR + Cert (mTLS)
CLIENT_KEY="$OUT_DIR/snapclient.key"
CLIENT_CSR="$OUT_DIR/snapclient.csr"
CLIENT_CRT="$OUT_DIR/snapclient.crt"
CLIENT_CFG="$OUT_DIR/.tmp-client.cnf"

if [ ! -s "$CLIENT_CRT" ]; then
    echo ">> Creating Client-Certificate..."

cat >"$CLIENT_CFG" <<EOF
[ req ]
default_md = sha256
prompt = no
distinguished_name = dn
req_extensions = req_ext

[ dn ]
C = $C
ST = $ST
L = $L
O = $ORG_CLIENT
CN = $CLIENT_CN

[ req_ext ]
subjectAltName = DNS:$CLIENT_CN
keyUsage = digitalSignature
extendedKeyUsage = clientAuth

[ x509_ext ]
subjectAltName = DNS:$CLIENT_CN
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
EOF

    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$CLIENT_KEY"
    openssl req -new -sha256 -key "$CLIENT_KEY" -out "$CLIENT_CSR" -config "$CLIENT_CFG"
    openssl x509 -req -in "$CLIENT_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$CLIENT_CRT" -days "$CLIENT_DAYS" -sha256 \
    -extfile "$CLIENT_CFG" -extensions x509_ext

else
    echo ">> Client-Certificate is already existing, skipping."
fi

# 4) Update file permissions
chmod 600 "$OUT_DIR"/*.key || true

echo
echo "Done. CA and certificates are located in: $(realpath "$OUT_DIR")"
printf "  CA:      %s\n" "$(realpath "$CA_CRT")"
printf "  Server:  %s  (Key: %s)\n" "$(realpath "$SERVER_CRT")" "$(realpath "$SERVER_KEY")"
printf "  Client:  %s  (Key: %s)\n" "$(realpath "$CLIENT_CRT")" "$(realpath "$CLIENT_KEY")"

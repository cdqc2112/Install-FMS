#! /bin/bash

# csr - 1.1

# Create csr & Private key

# Create csr conf

cat > ${DOMAIN}.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
CN = ${DOMAIN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
EOF

openssl req -newkey rsa:2048 -nodes -keyout ${DOMAIN}.key -out ${DOMAIN}.csr -config ${DOMAIN}.conf
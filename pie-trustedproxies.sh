#!/bin/bash
set -e

LIST_FILE="/etc/apache2/trusted-proxies.list"

TMP_FILES=()
do_cleanup () {
  rm -- "${TMP_FILES[@]}"
}
trap do_cleanup EXIT

OUTPUT_FILE=$(mktemp); TMP_FILES+=("$OUTPUT_FILE")
if curl --silent --fail --remote-time -o "$OUTPUT_FILE" "${APACHE_REMOTEIP_TRUSTEDPROXYLIST_URL:-$1}"; then
    cp "$OUTPUT_FILE" "$LIST_FILE"
fi

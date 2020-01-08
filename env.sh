#!/bin/sh

echo "Setup environment variables"

set -e

export PKG_CONFIG_ALLOW_CROSS=1
export CARGO_INCREMENTAL=1
export RUST_LOG=indy=trace
export RUST_TEST_THREADS=1

# OpenSSL path changes with version number, so export OPENSSL_DIR=/usr/local/Cellar/openssl/1.0.2n would not work correctly
OPENSSL_PATH=/usr/local/Cellar/openssl@1.1
for i in $(ls -t $OPENSSL_PATH); do
    export OPENSSL_VERSION=$i
    export OPENSSL_DIR=$OPENSSL_PATH/$OPENSSL_VERSION
    break
done

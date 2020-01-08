#!/bin/sh

# setup.sh has been successful executed

source ./env.sh

OUTPUT_DIR=./output
INDY_SDK_DIR=./indy-sdk
VCX_DIR=${INDY_SDK_DIR}/vcx

# Clone indy-sdk?
# Checkout required version
# Build libindy

# Build libssl and libcrypto
build_crypto() {
    if [ ! -d $OUTPUT_DIR/OpenSSL-for-iPhone ]; then
        git clone https://github.com/x2on/OpenSSL-for-iPhone.git $OUTPUT_DIR/OpenSSL-for-iPhone
    fi
    pushd $OUTPUT_DIR/OpenSSL-for-iPhone
    pwd
    ./build-libssl.sh --version=$OPENSSL_VERSION
    popd

    # Check there is a fat file output/OpenSSL-for-iPhone/lib/libssl.a
    # Check there is a fat file output/OpenSSL-for-iPhone/lib/libcrypto.a
}

# Build libsodium
build_libsodium() {
    if [ ! -d $OUTPUT_DIR/libsodium-ios ]; then
        git clone https://github.com/evernym/libsodium-ios.git $OUTPUT_DIR/libsodium-ios
    fi

    pushd $OUTPUT_DIR/libsodium-ios
    pwd
    ./libsodium.rb
    popd

    # Check there is a fat file output/libsodium-ios/dist/ios/lib/libsodium.a
}

# Build libzmq
build_libzmq() {
    if [ ! -d $OUTPUT_DIR/libzmq-ios ]; then
        git clone https://github.com/evernym/libzmq-ios.git $OUTPUT_DIR/libzmq-ios
    fi

    pushd $OUTPUT_DIR/libzmq-ios
    pwd
    git apply ../../libzmq.rb.patch
    ./libzmq.rb
    popd

    # Check there is a fat file output/libzmq-ios/dist/ios/lib/libzmq.a
}

extract_architectures() {
    ARCHS="arm64 x86_64"
    FILE_PATH=$1
    LIB_NAME=$2

    echo FILE_PATH=$FILE_PATH
    echo LIB_NAME=$LIB_NAME

    mkdir -p tmp
    pushd tmp

    echo "Extracting architectures for $LIB_NAME..."
    for ARCH in ${ARCHS[*]}; do
        echo $ARCH
        mkdir -p ${ARCH}
        lipo -extract ${ARCH} ../$FILE_PATH -o ${ARCH}/$LIB_NAME-fat.a
        lipo ${ARCH}/$LIB_NAME-fat.a -thin $ARCH -output ${ARCH}/$LIB_NAME.a
        rm ${ARCH}/$LIB_NAME-fat.a
    done
    popd

    # Check tmp/arm64/$LIB_NAME.a is non-fat file with arm64 architecture
    # Check tmp/x86_64/$LIB_NAME.a is non-fat file with x86_64 architecture

    # For example
    # $ lipo -info tmp/arm64/libzmq.a
    # Non-fat file: tmp/arm64/libzmq.a is architecture: arm64
}

# Build vcx

# Copy libraries to combine
# Combine libs by arch
# Merge libs to single fat binary

# build_crypto
# build_libsodium
# build_libzmq

# extract_architectures LIB_PATH LIB_NAME
# extract_architectures output/libzmq-ios/dist/ios/lib/libzmq.a libzmq

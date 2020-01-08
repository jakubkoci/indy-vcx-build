#!/bin/sh

# setup.sh has been successful executed

source ./env.sh

INDY_VERSION="v1.13.0"
OUTPUT_DIR=./output
INDY_SDK_DIR=$OUTPUT_DIR/indy-sdk

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
    LIB_FILE_NAME=$2
    LIB_NAME=$3

    echo FILE_PATH=$FILE_PATH
    echo LIB_FILE_NAME=$LIB_FILE_NAME

    mkdir -p $OUTPUT_DIR/libs
    pushd $OUTPUT_DIR/libs

    echo "Extracting architectures for $LIB_FILE_NAME..."
    for ARCH in ${ARCHS[*]}; do
        DESTINATION=${LIB_NAME}/${ARCH}

        echo "Destination $DESTINATION"

        mkdir -p $DESTINATION
        lipo -extract ${ARCH} ../../$FILE_PATH -o $DESTINATION/$LIB_FILE_NAME-fat.a
        lipo $DESTINATION/$LIB_FILE_NAME-fat.a -thin $ARCH -output $DESTINATION/$LIB_FILE_NAME.a
        rm $DESTINATION/$LIB_FILE_NAME-fat.a
    done

    popd

    # Check $OUTPUT_DIR/libs/arm64/$LIB_NAME.a is non-fat file with arm64 architecture
    # Check $OUTPUT_DIR/libs/x86_64/$LIB_NAME.a is non-fat file with x86_64 architecture

    # For example
    # $ lipo -info output/libs/arm64/libzmq.a
    # Non-fat file: output/libs/arm64/libzmq.a is architecture: arm64
}

checkout_indy_sdk() {
    if [ ! -d $INDY_SDK_DIR ]; then
        git clone https://github.com/hyperledger/indy-sdk $INDY_SDK_DIR
    fi

    pushd $INDY_SDK_DIR
    git fetch --all
    git checkout $INDY_VERSION
    popd
}

build_libindy() {
    # OpenSSL-for-iPhone currently provides libs only for aarch64-apple-ios and x86_64-apple-ios, so we select only them.
    TRIPLETS="aarch64-apple-ios,x86_64-apple-ios"

    pushd $INDY_SDK_DIR/libindy
    cargo lipo --release --targets="${TRIPLETS}"
    popd

    # Check there is a non-fat file $INDY_SDK_DIR/libindy/target/$TRIPLET/release/libindy.a
}

copy_libindy_architectures() {
    ARCHS="arm64 x86_64"
    LIB_NAME="indy"

    # mkdir -p $OUTPUT_DIR/libs
    # pushd $OUTPUT_DIR/libs

    echo "Copying architectures for $LIB_NAME..."
    for ARCH in ${ARCHS[*]}; do
        generate_flags $ARCH

        echo ARCH=$ARCH
        echo TRIPLET=$TRIPLET

        mkdir -p $OUTPUT_DIR/libs/$LIB_NAME/$ARCH
        # lipo -extract $TRIPLET ${ARCH}/libindy.a -o ${ARCH}/libindy.a
        # ${libtool} -static ${ARCH}/libindy.a -o ${ARCH}/libindy_libtool.a
        # mv ${ARCH}/libindy_libtool.a ${ARCH}/libindy.a

        cp -v $INDY_SDK_DIR/libindy/target/$TRIPLET/release/libindy.a $OUTPUT_DIR/libs/$LIB_NAME/$ARCH/libindy.a
    done
}

build_libvcx() {
    WORK_DIR=$(abspath "$OUTPUT_DIR")
    ARCHS="arm64 x86_64"

    echo WORK_DIR=$WORK_DIR

    pushd $INDY_SDK_DIR/vcx/libvcx
    for ARCH in ${ARCHS[*]}; do
        generate_flags $ARCH

        echo ARCH=$ARCH
        echo TRIPLET=$TRIPLET

        export OPENSSL_LIB_DIR=$WORK_DIR/libs/openssl/${ARCH}
        export IOS_SODIUM_LIB=$WORK_DIR/libs/sodium/${ARCH}
        export IOS_ZMQ_LIB=$WORK_DIR/libs/zmq/${ARCH}
        export LIBINDY_DIR=$WORK_DIR/libs/indy/${ARCH}

        cargo build --target "${TRIPLET}" --release --no-default-features --features "ci"
    done
    popd

    # Check there is a non-fat file $INDY_SDK_DIR/vcx/libvcx/target/$TRIPLET/release/libindy.a
}

copy_libvcx_architectures() {
    ARCHS="arm64 x86_64"
    LIB_NAME="vcx"

    mkdir -p $OUTPUT_DIR/libs

    echo "Copying architectures for $LIB_NAME..."
    for ARCH in ${ARCHS[*]}; do
        generate_flags $ARCH

        echo ARCH=$ARCH
        echo TRIPLET=$TRIPLET

        mkdir -p $OUTPUT_DIR/libs/$LIB_NAME/$ARCH
        
        cp -v $INDY_SDK_DIR/vcx/libvcx/target/$TRIPLET/release/libvcx.a $OUTPUT_DIR/libs/$LIB_NAME/$ARCH/libvcx.a
    done
}

generate_flags() {
    if [ -z $1 ]; then
        echo "please provide the arch e.g. arm64 or x86_64"
        exit 1
    fi

    if [ $1 == "arm64" ]; then
        export TRIPLET="aarch64-apple-ios"
    elif [ $1 == "x86_64" ]; then
        export TRIPLET="x86_64-apple-ios"
    fi
}

abspath() {
    # generate absolute path from relative path
    # $1     : relative filename
    # return : absolute path
    if [ -d "$1" ]; then
        # dir
        (
            cd "$1"
            pwd
        )
    elif [ -f "$1" ]; then
        # file
        if [[ $1 = /* ]]; then
            echo "$1"
        elif [[ $1 == */* ]]; then
            echo "$(
                cd "${1%/*}"
                pwd
            )/${1##*/}"
        else
            echo "$(pwd)/$1"
        fi
    fi
}

# build_crypto
# build_libsodium
# build_libzmq

# We introduce library names as third parameter of extract_architectures becuase VCX cargo build requires OPENSSL_LIB_DIR variable for folder with both OpenSSL libs (libssl and libcrypto) toghether.
# extract_architectures LIB_PATH LIB_FILE_NAME and LIB_NAME
# extract_architectures output/libsodium-ios/dist/ios/lib/libsodium.a libsodium sodium
# extract_architectures output/libzmq-ios/dist/ios/lib/libzmq.a libzmq zmq
# extract_architectures output/OpenSSL-for-iPhone/lib/libssl.a libssl openssl
# extract_architectures output/OpenSSL-for-iPhone/lib/libcrypto.a libcrypto openssl

# Build libindy
# checkout_indy_sdk
# build_libindy
# copy_libindy_architectures

# Build vcx
# build_libvcx
copy_libvcx_architectures

# Copy libraries to combine
# Combine libs by arch
# Merge libs to single fat binary

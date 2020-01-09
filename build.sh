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
    ./build-libssl.sh --version=$OPENSSL_VERSION
    popd

    # Check there is a fat file libssl.a
    lipo -info $OUTPUT_DIR/OpenSSL-for-iPhone/lib/libssl.a

    # Check there is a fat file libcrypto.a
    lipo -info $OUTPUT_DIR/OpenSSL-for-iPhone/lib/libcrypto.a
}

# Build libsodium
build_libsodium() {
    if [ ! -d $OUTPUT_DIR/libsodium-ios ]; then
        git clone https://github.com/evernym/libsodium-ios.git $OUTPUT_DIR/libsodium-ios
    fi

    pushd $OUTPUT_DIR/libsodium-ios
    ./libsodium.rb
    popd

    # Check there is a fat file libsodium.a
    lipo -info $OUTPUT_DIR/libsodium-ios/dist/ios/lib/libsodium.a
}

# Build libzmq
build_libzmq() {
    if [ ! -d $OUTPUT_DIR/libzmq-ios ]; then
        git clone https://github.com/evernym/libzmq-ios.git $OUTPUT_DIR/libzmq-ios
    fi

    pushd $OUTPUT_DIR/libzmq-ios
    git apply ../../libzmq.rb.patch
    ./libzmq.rb
    popd

    # Check there is a fat file libzmq.a
    lipo -info $OUTPUT_DIR/libzmq-ios/dist/ios/lib/libzmq.a
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

copy_libs_tocombine() {
    mkdir -p $OUTPUT_DIR/cache/arch_libs

    copy_lib_tocombine openssl libssl
    copy_lib_tocombine openssl libcrypto
    copy_lib_tocombine sodium libsodium
    copy_lib_tocombine zmq libzmq
    copy_lib_tocombine indy libindy
    copy_lib_tocombine vcx libvcx
}

copy_lib_tocombine() {
    LIB_NAME=$1
    LIB_FILE_NAME=$2

    ARCHS="arm64 x86_64"

    for ARCH in ${ARCHS[*]}; do
        cp -v $OUTPUT_DIR/libs/$LIB_NAME/$ARCH/$LIB_FILE_NAME.a $OUTPUT_DIR/cache/arch_libs/${LIB_FILE_NAME}_$ARCH.a
    done
}

combine_libs() {
    COMBINED_LIB=$1

    BUILD_CACHE=$(abspath "$OUTPUT_DIR/cache")
    libtool="/usr/bin/libtool"

    ARCHS="arm64 x86_64"

    # Combine results of the same architecture into a library for that architecture
    source_combined=""
    for arch in ${ARCHS[*]}; do
        libraries="libssl libcrypto libsodium libzmq libindy libvcx"

        echo libraries
        echo $libraries

        source_libraries=""

        for library in ${libraries[*]}; do
            echo "Stripping library"
            echo $library
            if [ "$DEBUG_SYMBOLS" = "nodebug" ]; then
                if [ "${library}" = "libvcx.a.tocombine" ]; then
                    rm -rf ${BUILD_CACHE}/arch_libs/${library}-$arch-stripped.a
                    strip -S -x -o ${BUILD_CACHE}/arch_libs/${library}-$arch-stripped.a -r ${BUILD_CACHE}/arch_libs/${library}_${arch}.a
                elif [ ! -f ${BUILD_CACHE}/arch_libs/${library}-$arch-stripped.a ]; then
                    strip -S -x -o ${BUILD_CACHE}/arch_libs/${library}-$arch-stripped.a -r ${BUILD_CACHE}/arch_libs/${library}_${arch}.a
                fi
                source_libraries="${source_libraries} ${BUILD_CACHE}/arch_libs/${library}-$arch-stripped.a"
            else
                source_libraries="${source_libraries} ${BUILD_CACHE}/arch_libs/${library}_${arch}.a"
            fi
        done

        echo "Using source_libraries: ${source_libraries} to create ${BUILD_CACHE}/arch_libs/${COMBINED_LIB}_${arch}.a"
        rm -rf "${BUILD_CACHE}/arch_libs/${COMBINED_LIB}_${arch}.a"
        $libtool -static ${source_libraries} -o "${BUILD_CACHE}/arch_libs/${COMBINED_LIB}_${arch}.a"
        source_combined="${source_combined} ${BUILD_CACHE}/arch_libs/${COMBINED_LIB}_${arch}.a"

        lipo -info ${BUILD_CACHE}/arch_libs/${COMBINED_LIB}_${arch}.a

        # TEMPORARY HACK (build libvcx without duplicate .o object files):
        # There are duplicate .o object files inside the libvcx.a file and these
        # lines of logic remove those duplicate .o object files
        rm -rf ${BUILD_CACHE}/arch_libs/tmpobjs
        mkdir ${BUILD_CACHE}/arch_libs/tmpobjs
        pushd ${BUILD_CACHE}/arch_libs/tmpobjs
        ar -x ../${COMBINED_LIB}_${arch}.a
        ls >../objfiles
        xargs ar cr ../${COMBINED_LIB}_${arch}.a.new <../objfiles
        if [ "$DEBUG_SYMBOLS" = "nodebug" ]; then
            strip -S -x -o ../${COMBINED_LIB}_${arch}.a.stripped -r ../${COMBINED_LIB}_${arch}.a.new
            mv ../${COMBINED_LIB}_${arch}.a.stripped ../${COMBINED_LIB}_${arch}.a
        else
            mv ../${COMBINED_LIB}_${arch}.a.new ../${COMBINED_LIB}_${arch}.a
        fi
        popd
    done

    echo "Using source_combined: ${source_combined} to create ${COMBINED_LIB}.a"
    # Merge the combined library for each architecture into a single fat binary
    lipo -create $source_combined -o $OUTPUT_DIR/${COMBINED_LIB}.a

    # Delete intermediate files
    rm -rf ${source_combined}

    # Show info on the output library as confirmation
    echo "Combination complete."
    lipo -info $OUTPUT_DIR/${COMBINED_LIB}.a
}

build_vcx_framework() {
    COMBINED_LIB=$1
    DATETIME=$(date +"%Y%m%d.%H%M")
    ARCHS="arm64 x86_64"

    cp -v $OUTPUT_DIR/${COMBINED_LIB}.a $INDY_SDK_DIR/vcx/wrappers/ios/vcx/lib/libvcx.a

    pushd $INDY_SDK_DIR/vcx/wrappers/ios/vcx
    rm -rf vcx.framework.previousbuild

    for ARCH in ${ARCHS[*]}; do
        echo $ARCH

        rm -rf vcx.framework
        if [ "${ARCH}" = "i386" ] || [ "${ARCH}" = "x86_64" ]; then
            # This sdk supports i386 and x86_64
            IPHONE_SDK=iphonesimulator
        elif [ "${ARCH}" = "armv7" ] || [ "${ARCH}" = "armv7s" ] || [ "${ARCH}" = "arm64" ]; then
            # This sdk supports armv7, armv7s, and arm64
            IPHONE_SDK=iphoneos
        else
            echo "Missing IPHONE_SDK value!"
            exit 1
        fi

        xcodebuild -project vcx.xcodeproj -scheme vcx -configuration Debug -arch ${ARCH} -sdk ${IPHONE_SDK} CONFIGURATION_BUILD_DIR=. build

        if [ -d "./vcx.framework.previousbuild" ]; then
            lipo -create -output combined.ios.vcx vcx.framework/vcx vcx.framework.previousbuild/vcx
            mv combined.ios.vcx vcx.framework/vcx
            rm -rf vcx.framework.previousbuild
        fi
        cp -rp vcx.framework vcx.framework.previousbuild
    done

    rm lib/libvcx.a
    rm -rf vcx.framework.previousbuild
    mkdir -p vcx.framework/Headers
    cp -v ConnectMeVcx.h vcx.framework/Headers
    cp -v include/libvcx.h vcx.framework/Headers
    cp -v vcx/vcx.h vcx.framework/Headers
    if [ -d tmp ]; then
        rm -rf tmp
    fi
    mkdir -p tmp/vcx/
    cp -rvp vcx.framework tmp/vcx/
    cd tmp

    zip -r vcx.${COMBINED_LIB}_${DATETIME}_universal.zip vcx
    popd

    cp $INDY_SDK_DIR/vcx/wrappers/ios/vcx/tmp/vcx.${COMBINED_LIB}_${DATETIME}_universal.zip $OUTPUT_DIR/
}

apply_vcx_wrapper_ios_patch() {
    pushd $INDY_SDK_DIR
    git apply ../../vcx-wrapper-ios.patch
    popd
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
# copy_libvcx_architectures

# Copy libraries to combine
# copy_libs_tocombine

# Combine libs by arch and merge libs to single fat binary
# combine_libs libvcxall

# Build vcx.framework
# apply_vcx_wrapper_ios_patch
# build_vcx_framework libvcxall

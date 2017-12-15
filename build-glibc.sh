#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

usage() {
    echo "usage: $(basename "$0") ARCH VERSION

Arguments:
    ARCH              Architecture to build glibc on.
    VERSION           Version of glibc to build.
"
}

running_in_docker() {
    cat /proc/1/cgroup | cut -d':' -f3 | grep -q "^/docker/"
}

SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT")"

ARCH="${1:-UNSET}"
GLIBC_VERSION="${2:-UNSET}"
GLIBC_URL="http://ftp.gnu.org/gnu/glibc/glibc-$GLIBC_VERSION.tar.gz"

if [ "$ARCH" = "UNSET" ]; then
    echo "ERROR: architecture missing."
    usage
    exit 1
elif [ "$GLIBC_VERSION" = "UNSET" ]; then
    echo "ERROR: glibc version missing."
    usage
    exit 1
fi

# Handle the architecture.
case "$ARCH" in
    x86_64)
        DOCKER_GLIBC_BUILDER_ARCH=amd64
        ;;
    x86)
        DOCKER_GLIBC_BUILDER_ARCH=i386
        ;;
    armhf)
        DOCKER_GLIBC_BUILDER_ARCH=armhf
        ;;
    aarch64)
        DOCKER_GLIBC_BUILDER_ARCH=arm64
        ;;
    *)
        echo "ERROR: Invalid architecture '$ARCH'."
        exit 1;;
esac

if running_in_docker; then
    SOURCE_DIR=/glibc-src
    BUILD_DIR=/glibc-build
    INSTALL_DIR=/glibc-install

    mkdir -p "$SOURCE_DIR" "$BUILD_DIR" "$INSTALL_DIR"

    # Download glibc.
    echo "Downloading glibc..."
    curl -# -L "$GLIBC_URL" | tar xz --strip 1 -C "$SOURCE_DIR"

    # Compile glibc.
    echo "Compiling glibc..."
    cd "$BUILD_DIR"
    "$SOURCE_DIR"/configure \
        --prefix="$INSTALL_DIR" \
        --libdir="$INSTALL_DIR/lib" \
        --libexecdir="$INSTALL_DIR/lib" \
        --enable-multi-arch
    make && make install

    echo "Creating glibc binary package..."
    (cd "$INSTALL_DIR" && tar --hard-dereference -zcf "/output/glibc-bin-${GLIBC_VERSION}-${ARCH}.tar.gz" *)
else
    # Create the Dockerfile.
    cat > Dockerfile <<EOF
FROM multiarch/ubuntu-debootstrap:${DOCKER_GLIBC_BUILDER_ARCH}-slim
RUN \
    apt-get -q update && \
    apt-get -qy install build-essential wget openssl gawk curl
ADD $(basename "$SCRIPT") /
VOLUME ["/output"]
ENTRYPOINT ["/build-glibc.sh"]
EOF

    # Build the docker image.
    (cd "$SCRIPT_DIR" && docker build -t glibc-builder .)

    # Run the glibc builder.
    mkdir -p "$SCRIPT_DIR"/build
    docker run --rm -v "$SCRIPT_DIR"/build:/output glibc-builder "$ARCH" "$GLIBC_VERSION"
fi


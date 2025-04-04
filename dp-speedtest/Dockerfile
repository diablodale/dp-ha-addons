# https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
ARG BUILD_FROM
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# python can included with the -python images

# set to our add-on persistent data directory
#WORKDIR /data

# Speedtest CLI version
ARG SPEEDTEST_VERSION="1.2.0"
ARG BUILD_ARCH

# Download and install speedtest-cli based on architecture
RUN if [ "${BUILD_ARCH}" == "i386" ]; then \
        SPEEDTEST_ARCH="i386"; \
    elif [ "${BUILD_ARCH}" == "amd64" ]; then \
        SPEEDTEST_ARCH="x86_64"; \
    elif [ "${BUILD_ARCH}" == "armhf" ] || [ "${BUILD_ARCH}" == "armv7" ]; then \
        SPEEDTEST_ARCH="armhf"; \
    elif [ "${BUILD_ARCH}" == "aarch64" ]; then \
        SPEEDTEST_ARCH="aarch64"; \
    else \
        echo "Unsupported architecture: ${BUILD_ARCH}" && \
        exit 1; \
    fi && \
    SPEEDTEST_URL="https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VERSION}-linux-${SPEEDTEST_ARCH}.tgz" && \
    wget -O /tmp/speedtest.tgz "${SPEEDTEST_URL}" && \
    tar -xvzf /tmp/speedtest.tgz -C /usr/local/bin speedtest && \
    chmod +x /usr/local/bin/speedtest && \
    rm /tmp/speedtest.tgz

# Copy data for add-on
COPY run.sh /
RUN chmod a+x /run.sh
    #ln -s /usr/share/zoneinfo/UTC /etc/localtime

# declare application to run
CMD [ "/run.sh" ]

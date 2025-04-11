# https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
ARG BUILD_FROM
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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

# python dependencies
RUN pip install --no-cache-dir \
    asyncio \
    loguru \
    git+https://github.com/music-assistant/python-hass-client.git@f5c1f565feaac7fe2ac379bb1993640c2748a796

# Copy data for add-on
COPY run.sh run.py /
RUN chmod a+x /run.sh /run.py

# declare application to run
CMD [ "/run.sh" ]

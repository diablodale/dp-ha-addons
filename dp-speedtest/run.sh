#!/usr/bin/with-contenv bashio

# set log level
bashio::log.level "$(bashio::config 'log_level' 'info')"
bashio::log.notice "dp speedtest started"

##################
# eula and privacy
##################

# testing shows that EULA and Privacy Policy acceptance are recorded
# in /root/.config/ookla/speedtest-cli.json
# {
#   "Settings": {
#     "LicenseAccepted": "604ec27f828456331ebf441826292c49276bd3c1bee1a2f65a6452f505c4061c",
#     "GDPRTimeStamp": 1743729654
#   }
# }
# where
# - `LicenseAccepted` is recorded when EULA accepted; set to a SHA256 hash
# - `GDPRTimeStamp` is recorded when Privacy Policy accepted; set to current epoch timestamp
# and both, one, or none of these values may be present in the file.
# Any previous state of the file is retained and not overwritten when already valid.
# Using `speedtest --accept-license --accept-gdpr` will record any missing user acceptance.
# Therefore, it is unneeded to backup/restore the file with /data.

# check if user has accepted the EULA and Privacy Policy in the addon config UI
if bashio::config.false 'accept_eula' || bashio::config.false 'accept_privacy'; then
    bashio::log.fatal "Ookla requires you to accept their EULA and Privacy Policy."
    bashio::log.fatal "Please accept the EULA and Privacy Policy in the addon config UI."
    bashio::log.fatal "Shutdown."
    exit 1
fi

##################
# create ha resources
##################
bashio::log.debug "Create Home Assistant resources"

# workaround https://github.com/hassio-addons/bashio/issues/163
# returns {"name":"dp speedtest","slug":"local_dp-speedtest","hostname":"local-dp-speedtest","dns":["local-dp-speedtest.local.hass.io"], ...
#ADDON_INFO=$(bashio::addons 'self' 'addons.self.info' '.')
#bashio::log.info "Addon info: $ADDON_INFO"

# Get the expanded slug of the addon, e.g. `local_dp-speedtest`
# https://developers.home-assistant.io/docs/add-ons/communication#network
#ADDON_SLUG=$(bashio::jq "${ADDON_INFO}" '.slug')
ADDON_SLUG=$(bashio::addons 'self' "addons.self.slug" '.slug')
bashio::log.info "Addon slug: $ADDON_SLUG"

# hostname
ADDON_HOSTNAME=$(bashio::addon.hostname)
bashio::log.info "Addon hostname: $ADDON_HOSTNAME"

ADDON_NAME=$(bashio::addon.name)
bashio::log.info "Addon name: $ADDON_NAME"

ADDON_VERSION=$(bashio::addon.version)
bashio::log.info "Addon version: $ADDON_VERSION"

# Get the "model" from the test executable
# if model is empty or doesn't contain manufacturer, exit
MANUFACTURER="Ookla"
TEST_VERSION=$(su -c 'speedtest --version | head -n 1')
if [ -z "$TEST_VERSION" ] || ! echo "$TEST_VERSION" | grep -iq "$MANUFACTURER"; then
    bashio::log.error "speedtest is not built into the addon correctly. Shutdown."
    exit 1
fi

# parse the test version string
MODEL=$(echo "$TEST_VERSION" | sed -E 's/^([^0-9]+) [0-9].*/\1/')
MODEL_ID=$(echo $MODEL | sha1sum | head -c 10)
HW_VERSION=$(echo "$TEST_VERSION" | sed -E 's/^[^0-9]+([0-9]+(\.[0-9]+)+).*/\1/')

# Device specific to this addon from its specific repository
DEVICE_ID="${ADDON_SLUG}"
DEVICE_NAME="Internet Speed Monitor" # "${ADDON_NAME}"

# Create a timestamp for the test
TIMESTAMP=$(date +%s)
FORMATTED_TIME=$(date -d @${TIMESTAMP} -Iseconds)

# Create device JSON
# https://developers.home-assistant.io/docs/device_registry_index/
JSON_DATA=$(cat <<EOF
{
  "config_entries": ["${ADDON_SLUG}"],
  "connections": [],
  "identifiers": [["dp_speedtest", "${DEVICE_ID}"]],
  "manufacturer": "${MANUFACTURER}",
  "model": "${MODEL}",
  "model_id": "${MODEL_ID}",
  "name": "${DEVICE_NAME}",
  "sw_version": "${ADDON_VERSION}",
  "hw_version": "${HW_VERSION}"
}
EOF
)
bashio::log.info "Device JSON: ${JSON_DATA}"

# Create or update the device
#bashio::api.supervisor POST /core/api/device_registry "$json"

##################
# run single speedtest
##################
run_speedtest() {
    # get server id
    if bashio::config.has_value 'server_id'; then
        SERVER_ID="--server-id=$(bashio::config 'server_id')"
    else
        SERVER_ID=""
    fi

    # Update the lastrun timestamp
    # note that timestamp is updated regardless of the success of the speedtest
    touch /data/lastrun
    bashio::log.debug "Test running now"

    # run test or use static results
    if bashio::config.has_value 'static_results'; then
        bashio::log.debug "Test using: JSON Test Results from configuration"
        RESULTS_JSON=$(bashio::config 'static_results')
    else
        # record acceptance of EULA and privacy, run test
        # requires su with homeassistant base containers or leads to exception and crash
        RUN_CMD="speedtest --accept-license --accept-gdpr --format=json --progress=no ${SERVER_ID} > /data/speedtest-results.json"
        bashio::log.debug "Test using: $RUN_CMD"
        if ! su -c "$RUN_CMD"; then
            bashio::log.error "Test failed. Check the log for more information."
            return 1
        fi
        RESULTS_JSON=$(cat /data/speedtest-results.json)
    fi
    bashio::log.debug "Test JSON: $RESULTS_JSON"

    # Extract speed values
    DOWNLOAD_BANDWIDTH_BYTES=$(bashio::jq "$RESULTS_JSON" '.download.bandwidth')
    UPLOAD_BANDWIDTH_BYTES=$(bashio::jq "$RESULTS_JSON" '.upload.bandwidth')
    IDLE_LATENCY_MS=$(bashio::jq "$RESULTS_JSON" '.ping.latency')
    UPLOAD_LATENCY_MS=$(bashio::jq "$RESULTS_JSON" '.upload.latency.iqm')
    DOWNLOAD_LATENCY_MS=$(bashio::jq "$RESULTS_JSON" '.download.latency.iqm')

    # validate values
    if [ -z "$DOWNLOAD_BANDWIDTH_BYTES" ] || [ -z "$UPLOAD_BANDWIDTH_BYTES" ] || [ -z "$IDLE_LATENCY_MS" ] || [ -z "$UPLOAD_LATENCY_MS" ] || [ -z "$DOWNLOAD_LATENCY_MS" ]; then
        bashio::log.error "Unexpected test data: down MBps $DOWNLOAD_BANDWIDTH_BYTES, up $UPLOAD_BANDWIDTH_BYTES, idleL ms $IDLE_LATENCY_MS, downL $DOWNLOAD_LATENCY_MS, upL $UPLOAD_LATENCY_MS"
        return 1
    fi

    # Convert speed values to Mbps (mega bits per second)
    DOWNLOAD_BANDWIDTH_Mbps=$(printf "%.2f" $(echo "$DOWNLOAD_BANDWIDTH_BYTES * 8 / 1000000" | bc -l))
    UPLOAD_BANDWIDTH_Mbps=$(printf "%.2f" $(echo "$UPLOAD_BANDWIDTH_BYTES * 8 / 1000000" | bc -l))
    IDLE_LATENCY_MS=$(printf "%.0f" $IDLE_LATENCY_MS)
    UPLOAD_LATENCY_MS=$(printf "%.0f" $UPLOAD_LATENCY_MS)
    DOWNLOAD_LATENCY_MS=$(printf "%.0f" $DOWNLOAD_LATENCY_MS)

    # Report current results
    bashio::log.info "Test results: download: $DOWNLOAD_BANDWIDTH_Mbps Mbps ($DOWNLOAD_LATENCY_MS ms), upload: $UPLOAD_BANDWIDTH_Mbps Mbps ($UPLOAD_LATENCY_MS ms), ping: $IDLE_LATENCY_MS ms"

    # TODO push results to home assistant
    return 0
}

################
# Main loop
################
while true; do
    # Get the interval from config (default to 1440 minutes if not specified - 24 hours)
    INTERVAL_M=$(bashio::config 'interval' "1440")
    if bashio::config.has_value 'static_results'; then
        MIN_INTERVAL_M=1
    else
        MIN_INTERVAL_M=30
    fi
    if [ "$INTERVAL_M" -lt "$MIN_INTERVAL_M" ]; then
        bashio::log.warning "Test interval of $INTERVAL_M minutes is too small; using $MIN_INTERVAL_M minutes"
        INTERVAL_M=$MIN_INTERVAL_M
    fi
    INTERVAL_S=$((INTERVAL_M * 60))

    # Check when the last attempted run was
    if [ -f /data/lastrun ]; then
        # Get the timestamp of the last run file
        LAST_RUN_TIMESTAMP=$(stat -c %Y /data/lastrun)
        CURRENT_TIMESTAMP=$(date +%s)
        ELAPSED_S=$((CURRENT_TIMESTAMP - LAST_RUN_TIMESTAMP))
        bashio::log.debug "Last test attempt: $(date -d @"$LAST_RUN_TIMESTAMP") now: $(date -d @"$CURRENT_TIMESTAMP") elapsed: ${ELAPSED_S}/${INTERVAL_S}s"

        # Check if enough time has passed since the last run
        if [ $ELAPSED_S -ge $INTERVAL_S ]; then
            # Time to run the test
            run_speedtest
            # Continue loop to recalculate next sleep time immediately
            continue
        else
            # Calculate duration until next test run
            NEXT_TEST_S=$((INTERVAL_S - ELAPSED_S))
            NEXT_TEST_M=$((NEXT_TEST_S / 60))
            NEXT_TEST_TIMESTAMP=$(($(date +%s) + NEXT_TEST_S))
            NEXT_TEST_TIME=$(date -d@"$NEXT_TEST_TIMESTAMP" -Iminutes)

            # Cap maximum sleep time at 1 hour to reload config changes during wakeup
            MAX_SLEEP_S=3600
            SLEEP_TIME_S=$NEXT_TEST_S
            if [ $SLEEP_TIME_S -gt $MAX_SLEEP_S ]; then
                SLEEP_TIME_S=$MAX_SLEEP_S
                bashio::log.debug "Sleep time limited to 1 hour to load configuration changes"
            fi

            # Log next wakeup time (in minutes)
            NEXT_WAKEUP_M=$((SLEEP_TIME_S / 60))
            NEXT_WAKEUP_TIMESTAMP=$(($(date +%s) + SLEEP_TIME_S))
            NEXT_WAKEUP_TIME=$(date -d@"$NEXT_WAKEUP_TIMESTAMP" -Iminutes)
            bashio::log.info "Next wakeup at $NEXT_WAKEUP_TIME (in $NEXT_WAKEUP_M minutes). Next test at $NEXT_TEST_TIME (in $NEXT_TEST_M minutes)."

            # Sleep until next scheduled wakeup
            sleep ${SLEEP_TIME_S}s
        fi
    else
        # No previous run - run the speedtest immediately
        bashio::log.debug "Test lastrun timestamp file missing"
        run_speedtest
    fi
done

#!/usr/bin/with-contenv bashio

bashio::log.notice "Starting addon: dp speedtest"

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

    # run test or use static results
    if bashio::config.has_value 'static_results'; then
        bashio::log.debug "Simulate test with static test results from configuration"
        RESULTS_JSON=$(bashio::config 'static_results')
    else
        # record acceptance of EULA and privacy, run test
        # requires su with homeassistant base containers or leads to exception and crash
        RUN_CMD="speedtest --accept-license --accept-gdpr --format=json --progress=no ${SERVER_ID} > /data/speedtest-results.json"
        if ! su -c "$RUN_CMD"; then
            bashio:log.error "$RUN_CMD"
            bashio:log.error "Speedtest failed. Check the log for more information."
            return 1
        fi
        bashio:log.debug "$RUN_CMD"
        RESULTS_JSON=$(cat /data/speedtest-results.json)
    fi

    # Extract speed values
    DOWNLOAD_BANDWIDTH_BYTES=$(bashio::jq "$RESULTS_JSON" '.download.bandwidth')
    UPLOAD_BANDWIDTH_BYTES=$(bashio::jq "$RESULTS_JSON" '.upload.bandwidth')
    IDLE_LATENCY_MS=$(bashio::jq "$RESULTS_JSON" '.ping.latency')
    UPLOAD_LATENCY_MS=$(bashio::jq "$RESULTS_JSON" '.upload.latency.iqm')
    DOWNLOAD_LATENCY_MS=$(bashio::jq "$RESULTS_JSON" '.download.latency.iqm')

    # validate values
    if [ -z "$DOWNLOAD_BANDWIDTH_BYTES" ] || [ -z "$UPLOAD_BANDWIDTH_BYTES" ] || [ -z "$IDLE_LATENCY_MS" ] || [ -z "$UPLOAD_LATENCY_MS" ] || [ -z "$DOWNLOAD_LATENCY_MS" ]; then
        bashio::log.error "Missing raw data: down MBps $DOWNLOAD_BANDWIDTH_BYTES, up $UPLOAD_BANDWIDTH_BYTES, idleL ms $IDLE_LATENCY_MS, downL $DOWNLOAD_LATENCY_MS, upL $UPLOAD_LATENCY_MS"
        return 1
    fi

    # Convert speed values to Mbps (mega bits per second)
    DOWNLOAD_BANDWIDTH_Mbps=$(echo "scale=2; $DOWNLOAD_BANDWIDTH_BYTES * 8 / 1000000" | bc)
    UPLOAD_BANDWIDTH_Mbps=$(echo "scale=2; $UPLOAD_BANDWIDTH_BYTES * 8 / 1000000" | bc)
    IDLE_LATENCY_MS=$(echo "scale=0; $IDLE_LATENCY_MS" | bc)
    UPLOAD_LATENCY_MS=$(echo "scale=0; $UPLOAD_LATENCY_MS" | bc)
    DOWNLOAD_LATENCY_MS=$(echo "scale=0; $DOWNLOAD_LATENCY_MS" | bc)
    bashio::log.debug "down Mbps $DOWNLOAD_BANDWIDTH_Mbps, up $UPLOAD_BANDWIDTH_Mbps, idleL ms $IDLE_LATENCY_MS, downL $DOWNLOAD_LATENCY_MS, upL $UPLOAD_LATENCY_MS"

    # Report current results
    bashio::log.info "Speedtest results:"
    bashio::log.info "Download: $DOWNLOAD_BANDWIDTH_Mbps Mbps ($DOWNLOAD_LATENCY_MS ms)"
    bashio::log.info "Upload: $UPLOAD_BANDWIDTH_Mbps Mbps ($UPLOAD_LATENCY_MS ms)"
    bashio::log.info "Ping: $IDLE_LATENCY_MS ms"

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
        bashio::log.warning "interval of $INTERVAL_M minutes is too low; using $MIN_INTERVAL_M minutes"
        INTERVAL_M=$MIN_INTERVAL_M
    fi
    INTERVAL_S=$((INTERVAL_M * 60))

    # Check when the last run was
    if [ -f /data/lastrun ]; then
        # Get the timestamp of the last run
        LAST_RUN_TIMESTAMP=$(stat -c %Y /data/lastrun)
        CURRENT_TIMESTAMP=$(date +%s)
        TIME_DIFF_S=$((CURRENT_TIMESTAMP - LAST_RUN_TIMESTAMP))
        bashio::log.trace "Schedule last: $(date -d @"$LAST_RUN_TIMESTAMP") now: $(date -d @"$CURRENT_TIMESTAMP") diff: ${TIME_DIFF_S}/${INTERVAL_S}"

        # Check if enough time has passed since the last run
        if [ $TIME_DIFF_S -ge $INTERVAL_S ]; then
            # Time to run the test
            run_speedtest
            # Continue loop to recalculate next sleep time immediately
            continue
        else
            # Calculate time until next run
            SLEEP_TIME_S=$((INTERVAL_S - TIME_DIFF_S))

            # Cap maximum sleep time at 1 hour to reload config changes
            MAX_SLEEP_S=3600
            if [ $SLEEP_TIME_S -gt $MAX_SLEEP_S ]; then
                SLEEP_TIME_S=$MAX_SLEEP_S
                bashio::log.info "Sleep time capped at 1 hour to handle configuration changes"
            fi

            # Log next run time (in minutes)
            NEXT_RUN_M=$((SLEEP_TIME_S / 60))
            NEXT_RUN_TIMESTAMP=$(($(date +%s) + SLEEP_TIME_S))
            NEXT_RUN_TIME=$(date -d@"$NEXT_RUN_TIMESTAMP" -Iminutes)
            bashio::log.info "Next speedtest scheduled at $NEXT_RUN_TIME (in $NEXT_RUN_M minutes)"

            # Sleep until next scheduled run or for maximum time
            bashio::log.debug "Sleeping for $SLEEP_TIME_S seconds"
            sleep ${SLEEP_TIME_S}s
        fi
    else
        # No previous run - run the speedtest immediately
        bashio::log.notice "Last run timestamp file missing - running test now"
        run_speedtest
    fi
done

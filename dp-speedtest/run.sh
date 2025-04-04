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

################
# scheduling
################

# Get the frequency from config (default to 1440 minutes if not specified - 24 hours)
FREQUENCY_MINUTES=$(bashio::config 'frequency' "1440")
FREQUENCY_SECONDS=$((FREQUENCY_MINUTES * 60))

# Check if lastrun file exists
if [ -f /data/lastrun ]; then
    # Get the timestamp of the last run
    LAST_RUN=$(stat -c %Y /data/lastrun)
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - LAST_RUN))
    bashio::log.trace "Schedule last: $(date -d @"$LAST_RUN") now: $(date -d @"$CURRENT_TIME") diff: $TIME_DIFF freq: $FREQUENCY_SECONDS"

    # Check if enough time has passed since the last run
    if [ $TIME_DIFF -lt $FREQUENCY_SECONDS ]; then
        # Exit early -- it's not time to run yet
        NEXT_RUN=$((FREQUENCY_SECONDS - TIME_DIFF))
        NEXT_RUN_MINUTES=$((NEXT_RUN / 60))
        bashio::log.info "Last speedtest was run $((TIME_DIFF / 60)) minutes ago."
        bashio::log.info "Next speedtest scheduled in $NEXT_RUN_MINUTES minutes."
        exit 0
    fi
fi

# get server id
SERVER_ID=""
if bashio::config.has_value 'server_id'; then
    SERVER_ID="--server-id=$(bashio::config 'server_id')"
fi

# Update the lastrun timestamp
# note that timestamp is updated regardless of the success of the speedtest
touch /data/lastrun

# record acceptance of EULA and privacy, run test
# requires su with homeassistant base containers or leads to exception and crash
RUN_CMD="speedtest --accept-license --accept-gdpr --format=json --progress=no ${SERVER_ID} > /data/speedtest-results.json"
if ! su -c "$RUN_CMD"; then
    bashio:log.error "$RUN_CMD"
    bashio:log.error "Speedtest failed. Check the log for more information."
    exit 0
fi
bashio:log.debug "$RUN_CMD"


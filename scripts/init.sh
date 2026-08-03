#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

LogAction "Set file permissions"

# if the user has not defined a PUID and PGID, throw an error and exit
if [ -z "${PUID}" ] || [ -z "${PGID}" ]; then
    LogError "PUID and PGID not set. Please set these in the environment variables."
    exit 1
else
    usermod -o -u "${PUID}" steam
    groupmod -o -g "${PGID}" steam
fi

# Every persistent path that must be owned by the configured PUID/PGID.
# This includes ALL Docker volume mount points plus the server home
# directory (server binaries, scripts, rcon config and DepotDownloader cache).
MANAGED_PATHS=(
    /project-zomboid                          # server-files volume
    "${CONFIG_DIR:-/project-zomboid-config}"  # server-data volume
    /home/steam                               # server home (scripts, rcon.yml, caches)
)

# Recursively apply the PUID/PGID ownership to every managed path.
apply_ownership() {
    chown -R steam:steam "${MANAGED_PATHS[@]}"
}

# Apply ownership up front so the steam user can write during install/config.
apply_ownership

cat /branding

if [ ! -f "/project-zomboid/start-server.sh" ]; then
    LogWarn "start-server.sh not found in server-files, forcing install regardless of UPDATE_ON_START"
    install
elif [ "${UPDATE_ON_START:-true}" = "true" ]; then
    install
else
    LogWarn "UPDATE_ON_START is set to false, skipping server update from Steam"
fi

# Configure memory settings
configure_memory

# Append extra VM args if specified
configure_vm_args

# Re-apply ownership so files created during install/config (which run as
# root) are handed back to the configured PUID/PGID across every mount.
LogAction "Applying PUID:PGID (${PUID}:${PGID}) ownership to all mounted directories"
apply_ownership

# shellcheck disable=SC2317
term_handler() {
    if ! shutdown_server; then
        # Does not save
        kill -SIGTERM "$(pidof ProjectZomboid64)"
    fi
    tail --pid="$killpid" -f 2>/dev/null
}

trap 'term_handler' SIGTERM

# Check config for warnings
check_admin_password

# Start the server as the steam (PUID:PGID) user so that every file it
# creates at runtime (saves, logs, configs across all mounted volumes) is
# owned by the configured PUID/PGID instead of root.
gosu steam ./start.sh &

# Process ID of the server launcher
killpid="$!"
wait "$killpid"
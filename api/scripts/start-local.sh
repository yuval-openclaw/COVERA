#!/bin/sh
# Starts the API on this Mac (used by the com.covera.api LaunchAgent).
#
# After a reboot, Postgres can refuse to start because postmaster.pid still
# names a process id that macOS has since given to an unrelated program, so it
# believes another server is running. This removes the lock only when that id
# is not a postgres process, then starts Postgres and waits for it.
PGDATA=/opt/homebrew/var/postgresql@17
PGBIN=/opt/homebrew/opt/postgresql@17/bin
LOCK="$PGDATA/postmaster.pid"

if ! "$PGBIN/pg_isready" -q; then
  if [ -f "$LOCK" ]; then
    pid=$(head -1 "$LOCK")
    if ! ps -o comm= -p "$pid" 2>/dev/null | grep -q postgres; then
      echo "start-local: removing stale Postgres lock (pid $pid is not postgres)"
      rm -f "$LOCK"
    fi
  fi
  /opt/homebrew/bin/brew services restart postgresql@17 >/dev/null 2>&1
  tries=0
  until "$PGBIN/pg_isready" -q || [ $tries -ge 30 ]; do
    sleep 1
    tries=$((tries + 1))
  done
fi

exec /opt/homebrew/bin/node --env-file=.env --import tsx src/server.ts

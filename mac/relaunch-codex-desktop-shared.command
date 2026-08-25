#!/bin/zsh
set -eu

# `launchctl submit` treats submitted jobs as KeepAlive services on current
# macOS releases. Refuse that execution mode so this one-shot helper can never
# become a quit/relaunch loop again.
if [[ "${XPC_SERVICE_NAME:-}" == com.codexcontroller.desktop-relaunch ]]; then
    launchctl remove com.codexcontroller.desktop-relaunch 2>/dev/null || true
    exit 2
fi

delay_seconds="${1:-8}"
sleep "$delay_seconds"

launchctl setenv CODEX_APP_SERVER_USE_LOCAL_DAEMON 1
osascript -e 'tell application id "com.openai.codex" to quit'

for _ in {1..100}; do
    if ! pgrep -x ChatGPT >/dev/null; then
        break
    fi
    sleep 0.1
done

open -a /Applications/ChatGPT.app

#!/bin/zsh
set +e

# Emergency rollback for the experimental Desktop shared-daemon mode.
launchctl remove com.codexcontroller.desktop-relaunch 2>/dev/null
launchctl remove com.codexcontroller.bridge 2>/dev/null
launchctl remove com.codexcontroller.app-server 2>/dev/null
launchctl unsetenv CODEX_APP_SERVER_USE_LOCAL_DAEMON

osascript -e 'tell application id "com.openai.codex" to quit'
for _ in {1..100}; do
    if ! pgrep -x ChatGPT >/dev/null; then
        break
    fi
    sleep 0.1
done
open -a /Applications/ChatGPT.app

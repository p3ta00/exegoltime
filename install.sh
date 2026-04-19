#!/usr/bin/env bash
set -e

INSTALL_PATH="/usr/local/bin/exegoltime"
LIBFAKETIME="/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

echo "[*] Installing exegoltime..."

# Check libfaketime
if [[ ! -f "$LIBFAKETIME" ]]; then
    echo "[!] libfaketime not found at $LIBFAKETIME"
    echo "[*] Installing..."
    apt-get install -y faketime 2>/dev/null || {
        echo "[!] Could not install libfaketime. Install manually: apt install faketime"
        exit 1
    }
fi

# Install script
cp "$(dirname "$0")/exegoltime.sh" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "[+] Installed to $INSTALL_PATH"

HOOK='
# ── exegoltime ──────────────────────────────────────────────────────────────
exegoltime() { source /usr/local/bin/exegoltime "$@"; }
[[ -f /tmp/.exegoltime_offset ]] && eval "$(source /tmp/.exegoltime_offset 2>/dev/null && printf "export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1\nexport FAKETIME=%s\nexport FAKETIME_NO_CACHE=1\nexport FAKETIME_DONT_FAKE_MONOTONIC=1" "${ET_OFFSET}")"
# ────────────────────────────────────────────────────────────────────────────'

# Add to zshrc
if [[ -f "$ZSHRC" ]]; then
    if grep -q 'exegoltime' "$ZSHRC"; then
        echo "[~] Already in $ZSHRC, skipping"
    else
        echo "$HOOK" >> "$ZSHRC"
        echo "[+] Added hook to $ZSHRC"
    fi
fi

# Add to bashrc if no zsh
if [[ ! -f "$ZSHRC" && -f "$BASHRC" ]]; then
    if grep -q 'exegoltime' "$BASHRC"; then
        echo "[~] Already in $BASHRC, skipping"
    else
        echo "$HOOK" >> "$BASHRC"
        echo "[+] Added hook to $BASHRC"
    fi
fi

echo "[+] Done. Reload your shell or run: source $ZSHRC"
echo ""
echo "Usage:"
echo "  exegoltime <target_ip>   # detect offset + activate"
echo "  exegoltime --status      # show current offset"
echo "  exegoltime --off         # disable"

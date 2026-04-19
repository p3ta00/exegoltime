#!/usr/bin/env bash
# exegoltime - Auto-detect target DC time offset and apply via LD_PRELOAD libfaketime
# Usage: exegoltime [target_ip]   (saves offset and activates it in current shell)
#        exegoltime --off          (disable faketime)
#        exegoltime --status       (show current offset)
#
# For persistent activation across sessions, add to ~/.zshrc:
#   source /usr/local/bin/exegoltime --load

LIBFAKETIME="/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1"
STATE_FILE="/tmp/.exegoltime_offset"

_ntp_time() {
    local ip="$1"
    python3 -c "
import socket, struct, time, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
try:
    s.sendto(b'\x1b' + 47*b'\x00', ('$ip', 123))
    data = s.recv(1024)
    t = struct.unpack('!12I', data)[10] - 2208988800
    print(int(t))
except Exception as e:
    print('ERR:' + str(e), file=sys.stderr)
    sys.exit(1)
finally:
    s.close()
" 2>/dev/null
}

_smb_time() {
    local ip="$1"
    python3 -c "
import socket, struct, time, sys
# Use NetBIOS session service to get time
try:
    import impacket
except ImportError:
    sys.exit(1)
" 2>/dev/null
}

exegoltime_off() {
    unset LD_PRELOAD FAKETIME FAKETIME_NO_CACHE FAKETIME_TIMESTAMP_FILE FAKETIME_DONT_FAKE_MONOTONIC
    rm -f "$STATE_FILE"
    echo "[exegoltime] faketime disabled"
}

exegoltime_status() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        echo "[exegoltime] Active: offset=${ET_OFFSET}s (${ET_OFFSET_HR}), target=${ET_TARGET}, detected at ${ET_DETECTED}"
        if [[ -n "$FAKETIME" ]]; then
            echo "[exegoltime] LD_PRELOAD=$LD_PRELOAD"
            echo "[exegoltime] FAKETIME=$FAKETIME"
        else
            echo "[exegoltime] WARNING: env vars not set in this shell — run: eval \$(exegoltime --load)"
        fi
    else
        echo "[exegoltime] Not active"
    fi
}

exegoltime_load() {
    # Emit export statements to be eval'd by the calling shell
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        echo "export LD_PRELOAD='$LIBFAKETIME'"
        echo "export FAKETIME='${ET_OFFSET}'"
        echo "export FAKETIME_NO_CACHE=1"
        echo "export FAKETIME_DONT_FAKE_MONOTONIC=1"
    else
        echo "echo '[exegoltime] No saved offset — run: exegoltime <target_ip>'" >&2
    fi
}

exegoltime_set() {
    local target="$1"

    if [[ -z "$target" ]]; then
        # Try to auto-detect from /etc/hosts or last known
        target=$(grep -E 'logging\.htb|\.htb' /etc/hosts 2>/dev/null | grep -v '^#' | head -1 | awk '{print $1}')
        if [[ -z "$target" ]]; then
            echo "[exegoltime] ERROR: No target IP. Usage: exegoltime <ip>" >&2
            return 1
        fi
        echo "[exegoltime] Auto-detected target: $target"
    fi

    echo -n "[exegoltime] Querying $target via NTP... "
    local remote_ts
    remote_ts=$(_ntp_time "$target")

    if [[ -z "$remote_ts" || "$remote_ts" == ERR* ]]; then
        echo "FAILED (NTP)"
        echo -n "[exegoltime] Trying SMB time query... "
        # Fallback: use impacket GetSessionKey or nmb
        remote_ts=$(python3 -c "
import socket, struct
# SMBv2 negotiate — get system time from header
s = socket.socket()
s.settimeout(3)
try:
    s.connect(('$target', 445))
    # SMBv2 negotiate request
    pkt = bytes.fromhex(
        '000000' + 'c0'  # NetBIOS session
        + 'feSMB'        # SMB2 magic
        + '40000000'     # StructureSize=64, CreditCharge=0
        + '0000'         # ChannelSequence/Reserved
        + '0000'         # Status
        + '0000'         # Command=NEGOTIATE
        + '0000'         # CreditRequest
        + '00000000'     # Flags
        + '00000000'     # NextCommand
        + '0000000000000000'  # MessageID
        + '00000000'     # Reserved
        + '00000000'     # TreeID
        + '0000000000000000'  # SessionID
        + '00000000000000000000000000000000'  # Signature
        # Negotiate body
        + '2400'         # StructureSize=36
        + '0200'         # DialectCount=2
        + '0100'         # SecurityMode
        + '0000'         # Reserved
        + '7f000000'     # Capabilities
        + '00000000000000000000000000000000'  # GUID
        + '0000000000000000'  # ClientStartTime
        + '0002'         # SMB2.02
        + '1002'         # SMB2.10
    )
    # rebuild with correct length
    body = bytes.fromhex(
        'feSMB' +
        '4000' + '0000' + '0000' + '0000' + '0000' + '00000000' + '00000000' +
        '0000000000000000' + '00000000' + '00000000' +
        '0000000000000000' +
        '00000000000000000000000000000000' +
        '2400' + '0200' + '0100' + '0000' +
        '7f000000' +
        '00000000000000000000000000000000' +
        '0000000000000000' +
        '0200' + '1002'
    )
    nb = b'\x00\x00\x00' + bytes([len(body)]) + body
    s.send(nb)
    resp = s.recv(256)
    # SMB2 negotiate response: system time at offset 40+4=44 from SMB2 header start
    # NetBIOS(4) + SMB2 header(64) + StructSize(2) + SecurityMode(2) + DialectRevision(2) + Reserved(2) + ServerGuid(16) + Capabilities(4) + MaxTransactSize(4) + MaxReadSize(4) + MaxWriteSize(4) = total 108 bytes before SystemTime
    if len(resp) > 108:
        ts_bytes = resp[108:116]
        # Windows FILETIME: 100ns intervals since 1601-01-01
        filetime = struct.unpack('<Q', ts_bytes)[0]
        unix_ts = (filetime - 116444736000000000) // 10000000
        print(int(unix_ts))
    s.close()
except Exception as e:
    import sys
    print('ERR:'+str(e), file=sys.stderr)
    s.close()
" 2>/dev/null)
    fi

    if [[ -z "$remote_ts" ]]; then
        echo "FAILED"
        echo "[exegoltime] Could not get time from $target. Check connectivity." >&2
        return 1
    fi

    local local_ts
    local_ts=$(date +%s)
    local offset=$(( remote_ts - local_ts ))
    local offset_hr

    if (( offset >= 0 )); then
        offset_hr="+$(( offset / 3600 ))h$(( (offset % 3600) / 60 ))m"
    else
        local abs=$(( -offset ))
        offset_hr="-$(( abs / 3600 ))h$(( (abs % 3600) / 60 ))m"
    fi

    # libfaketime requires explicit + for positive relative offsets
    local faketime_val
    if (( offset >= 0 )); then
        faketime_val="+${offset}"
    else
        faketime_val="${offset}"
    fi

    echo "OK"
    echo "[exegoltime] Local: $(date -u '+%Y-%m-%d %H:%M:%S UTC') | Remote: $(date -u -d @${remote_ts} '+%Y-%m-%d %H:%M:%S UTC') | Offset: ${offset}s (${offset_hr})"

    # Save state
    cat > "$STATE_FILE" << EOF
ET_TARGET="$target"
ET_OFFSET="${faketime_val}"
ET_OFFSET_HR="$offset_hr"
ET_DETECTED="$(date '+%Y-%m-%d %H:%M:%S')"
EOF

    # Set env in current shell
    export LD_PRELOAD="$LIBFAKETIME"
    export FAKETIME="${faketime_val}"
    export FAKETIME_NO_CACHE=1
    export FAKETIME_DONT_FAKE_MONOTONIC=1

    echo "[exegoltime] Activated: all commands in this shell now use remote time"
    echo "[exegoltime] To activate in a new shell: eval \$(exegoltime --load)"
}

# Dispatch
case "${1:-}" in
    --off|off|unset)  exegoltime_off ;;
    --status|status)  exegoltime_status ;;
    --load|load)      exegoltime_load ;;
    *)                exegoltime_set "$1" ;;
esac

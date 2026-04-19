# exegoltime

Auto-detect a target's clock offset and apply it system-wide via `libfaketime` — no more prefixing every command with `faketime`.

Built for Exegol, useful anywhere Kerberos clock skew gets in the way.

## The Problem

Active Directory environments (HTB, CTF labs, red team engagements) often run with clocks hours ahead of your attack machine. Every Kerberos tool (`impacket`, `certipy`, `krb5`, etc.) fails with:

```
KerberosError: KRB_AP_ERR_SKEW(Clock skew too great)
```

The usual fix is wrapping every command with `faketime '+25200' python3 ...` — tedious and easy to forget.

## The Fix

`exegoltime` detects the offset once, sets `LD_PRELOAD=libfaketime.so` in your shell, and every subsequent command automatically runs with the correct time.

## Install

```bash
# Inside Exegol (or any Linux host with libfaketime installed)
cp exegoltime.sh /usr/local/bin/exegoltime
chmod +x /usr/local/bin/exegoltime

# Add to ~/.zshrc for persistent auto-restore across sessions
echo '
exegoltime() { source /usr/local/bin/exegoltime "$@"; }
[[ -f /tmp/.exegoltime_offset ]] && eval $(source /tmp/.exegoltime_offset && echo "export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1; export FAKETIME=\"${ET_OFFSET}\"; export FAKETIME_NO_CACHE=1; export FAKETIME_DONT_FAKE_MONOTONIC=1")
' >> ~/.zshrc
```

## Usage

```bash
# Detect offset from target and activate in current shell
exegoltime 10.10.11.42

# Auto-detect target from /etc/hosts
exegoltime

# Restore saved offset in a new shell
eval $(exegoltime --load)

# Show current status
exegoltime --status

# Disable
exegoltime --off
```

## Example

```
$ exegoltime 10.10.11.42
[exegoltime] Querying 10.10.11.42 via NTP... OK
[exegoltime] Local: 2026-04-19 01:17:38 UTC | Remote: 2026-04-19 08:17:28 UTC | Offset: +25190s (+6h59m)
[exegoltime] Activated: all commands in this shell now use remote time

$ getTGT.py corp.htb/Administrator -hashes :aad3b435b51404eeaad3b435b51404ee:...
[*] Saving ticket in Administrator.ccache   ✓
```

## How It Works

1. Queries the target via NTP (UDP 123) to get its current timestamp
2. Falls back to SMBv2 negotiate response system time if NTP is blocked
3. Calculates the delta from local time
4. Exports `LD_PRELOAD` pointing to `libfaketime.so.1` with the offset
5. Saves state to `/tmp/.exegoltime_offset` — the zshrc hook auto-restores it on every new shell

## Requirements

- `libfaketime` (`apt install faketime`)
- `python3` (for NTP/SMB time queries)
- Exegol already ships both

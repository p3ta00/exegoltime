# exegoltime

Auto-detect a target's clock offset and apply it system-wide via `libfaketime` — no more prefixing every command with `faketime`.

Built for [Exegol](https://github.com/ThePorgs/Exegol), works on any Linux pentesting host.

---

## The Problem

AD labs (HTB, CTF, engagements) often run clocks hours ahead of your machine. Every Kerberos tool fails with:

```
KerberosError: KRB_AP_ERR_SKEW(Clock skew too great)
```

The usual fix is wrapping every single command:

```bash
faketime '+25200' getTGT.py ...
faketime '+25200' certipy ...
faketime '+25200' python3 exploit.py ...
```

## The Fix

Run `exegoltime <ip>` once. Every command in your shell automatically uses the correct time — no prefix needed.

```bash
$ exegoltime 10.10.11.42
[exegoltime] Querying 10.10.11.42 via NTP... OK
[exegoltime] Local: 2026-04-19 01:17:38 UTC | Remote: 2026-04-19 08:17:28 UTC | Offset: +25190s (+6h59m)
[exegoltime] Activated: all commands in this shell now use remote time

$ getTGT.py corp.htb/Administrator -hashes :...
[*] Saving ticket in Administrator.ccache
```

The offset persists across new shell sessions automatically.

---

## Install

```bash
git clone https://github.com/p3ta00/exegoltime
cd exegoltime
chmod +x install.sh
sudo ./install.sh
```

Then reload your shell:

```bash
source ~/.zshrc
```

### Requirements

- `libfaketime` — installed automatically by `install.sh` if missing (`apt install faketime`)
- `python3`

---

## Usage

```bash
exegoltime <target_ip>    # detect offset from target and activate in current shell
exegoltime                # auto-detect target from /etc/hosts
eval $(exegoltime --load) # restore saved offset in a new shell
exegoltime --status       # show active offset and target
exegoltime --off          # disable faketime
```

---

## How It Works

1. Queries the target via **NTP** (UDP 123) to get its timestamp
2. Falls back to **SMBv2** negotiate response if NTP is blocked
3. Calculates the delta from local time
4. Sets `LD_PRELOAD=libfaketime.so.1` + `FAKETIME=+<seconds>` in your shell
5. Saves state to `/tmp/.exegoltime_offset` — the shell hook restores it automatically on every new session

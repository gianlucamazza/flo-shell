#!/usr/bin/env python3
"""Stand-in for greetd, for dev/run-nested.sh ... greeter with FLO_AUTH=greetd.

Speaks the greetd IPC protocol (native-endian u32 length + JSON) on a Unix
socket and accepts one fixed secret for any user. It never starts anything:
start_session is only logged. Usage: fake-greetd.py SOCKET SECRET
"""
import json
import os
import socket
import struct
import sys


def recv_exact(conn, n):
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def send(conn, obj):
    payload = json.dumps(obj).encode()
    conn.sendall(struct.pack("=I", len(payload)) + payload)


def serve(conn, secret):
    authed = False
    while True:
        head = recv_exact(conn, 4)
        if head is None:
            return
        body = recv_exact(conn, struct.unpack("=I", head)[0])
        if body is None:
            return
        req = json.loads(body)
        kind = req.get("type")
        shown = dict(req)
        if "response" in shown:
            shown["response"] = "<%d chars>" % len(shown["response"] or "")
        print("request:", json.dumps(shown), flush=True)
        if kind == "create_session":
            authed = False
            send(conn, {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password:"})
        elif kind == "post_auth_message_response":
            if req.get("response") == secret:
                authed = True
                send(conn, {"type": "success"})
            else:
                send(conn, {"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"})
        elif kind == "start_session":
            if authed:
                print("WOULD START:", req.get("cmd"), req.get("env"), flush=True)
                send(conn, {"type": "success"})
            else:
                send(conn, {"type": "error", "error_type": "error", "description": "session not ready"})
        elif kind == "cancel_session":
            authed = False
            send(conn, {"type": "success"})
        else:
            send(conn, {"type": "error", "error_type": "error", "description": "unknown request"})


def main():
    path, secret = sys.argv[1], sys.argv[2]
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    print("fake greetd listening on", path, flush=True)
    while True:
        conn, _ = server.accept()
        try:
            serve(conn, secret)
        except (ConnectionError, ValueError) as err:
            print("connection ended:", err, flush=True)
        finally:
            conn.close()


if __name__ == "__main__":
    main()

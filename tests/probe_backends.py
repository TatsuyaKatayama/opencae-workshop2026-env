"""CI 専用。認証・LLM 呼び出しなしで ACP 初期ハンドシェイクを確認する。"""
import json
import os
import queue
import signal
import subprocess
import threading


def probe(command):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    responses = queue.Queue()

    def read():
        for line in process.stdout:
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if message.get('id') == 1:
                responses.put(message)
                return

    threading.Thread(target=read, daemon=True).start()
    try:
        request = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
            'protocolVersion': 1, 'clientCapabilities': {},
            'clientInfo': {'name': 'opencae-ci', 'version': '1.0.0'}}}
        process.stdin.write(json.dumps(request) + '\n')
        process.stdin.flush()
        try:
            response = responses.get(timeout=60)
        except queue.Empty:
            raise RuntimeError(f'{command[0]}: ACP initialize timed out') from None
        if 'error' in response or response.get('result', {}).get('protocolVersion') != 1:
            raise RuntimeError(f'{command[0]}: ACP initialize failed')
        print(f'{command[0]}: ACP initialize passed (no authentication or model call)')
    finally:
        # アダプターが起動した app-server 等も使い捨て CI 内で終了させる。
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        process.stdin.close()
        process.stdout.close()


if __name__ == '__main__':
    probe(['codex-acp'])
    probe(['opencode', 'acp'])

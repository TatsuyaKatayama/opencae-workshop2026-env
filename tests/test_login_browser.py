"""認証そのものを起動せず、URL と PowerShell 引数を確認する。"""
import base64
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'setup/ubuntu2404/login_browser.py'
spec = importlib.util.spec_from_file_location('login_browser', path)
browser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(browser)


class BrowserTest(unittest.TestCase):
    def test_only_authentication_urls(self):
        url = 'https://view.awsapps.com/start/#/device'
        self.assertEqual(browser.authentication_url('\x1b[32m'+url+'\x1b[0m\n'), url)
        for text in ('https://example.com/device', 'http://view.awsapps.com/device',
                     'https://view.awsapps.com.evil.example/device', 'https://user@view.awsapps.com/device'):
            self.assertIsNone(browser.authentication_url(text))

    def test_encoded_command_quotes_url_as_literal(self):
        url = "https://app.kiro.dev/signin?value=';echo BAD;#"
        command = browser.browser_command(url)
        self.assertEqual(command[0], 'powershell.exe')
        self.assertEqual(base64.b64decode(command[-1]).decode('utf-16le'),
                         "Start-Process -FilePath 'https://app.kiro.dev/signin?value='';echo BAD;#'")


if __name__ == '__main__':
    unittest.main()

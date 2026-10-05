#!/usr/bin/env python3
"""Local, one-use GitHub App/OpenRouter bootstrap. Secrets never leave .env.local.

Run from the repo root, then open http://localhost:3108. This is a local setup
tool, not a deployed route. Stop it after both credential exchanges finish.
"""
import base64
import hashlib
import html
import json
import os
from pathlib import Path
import secrets
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / 'backend/.env.local'
PORT = 3108
STARTED = time.monotonic()
STATE = secrets.token_urlsafe(32)
VERIFIER = secrets.token_urlsafe(48)
CONSUMED = set()


def read_env():
    result = {}
    for line in ENV_FILE.read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            value = value.strip()
            if value.startswith('"'):
                value = json.loads(value)
            else:
                value = value.strip("'")
            result[key] = value
    return result


def save_env(updates):
    lines = ENV_FILE.read_text().splitlines()
    keys = set(updates)
    for index, line in enumerate(lines):
        key = line.split('=', 1)[0]
        if key in updates:
            lines[index] = key + '=' + json.dumps(str(updates[key]))
            keys.discard(key)
    lines.extend(key + '=' + json.dumps(str(updates[key])) for key in sorted(keys))
    temporary = ENV_FILE.with_suffix('.local.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write('\n'.join(lines) + '\n')
    temporary.replace(ENV_FILE)
    os.chmod(ENV_FILE, 0o600)


def exchange(url, body=None):
    payload = json.dumps(body).encode() if body is not None else b''
    request = Request(url, data=payload, headers={
        'Content-Type': 'application/json', 'Accept': 'application/json',
        'User-Agent': 'Shiplog-credential-setup',
    }, method='POST')
    with urlopen(request, timeout=30) as response:
        return json.load(response)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # Callback URLs contain one-time secrets.

    def respond(self, body, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.headers.get('Host') not in (f'localhost:{PORT}', f'127.0.0.1:{PORT}'):
            return self.respond('Invalid host.', 403)
        if time.monotonic() - STARTED > 3600:
            return self.respond('Setup expired. Restart the local tool.', 410)
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        env = read_env()
        origin = urlparse(env['SHIPLOG_PUBLIC_URL'])
        if origin.scheme != 'https' or origin.path not in ('', '/') or origin.query or origin.fragment:
            return self.respond('Configure a valid SHIPLOG_PUBLIC_URL first.', 500)
        public = f'https://{origin.netloc}'
        if parsed.path == '/':
            return self.respond('<h1>Shiplog credentials</h1><p>Credentials are saved only in the ignored backend/.env.local file.</p>'
                '<p><a href="/github">Create the GitHub App</a></p><p><a href="/openrouter">Create a dedicated OpenRouter key</a></p>')
        if parsed.path == '/github':
            if env.get('GITHUB_APP_ID'):
                return self.respond('GitHub App credentials already configured. No duplicate created.')
            manifest = {
                'name': 'Shiplog Journal', 'url': public, 'public': True,
                'description': 'A developer journal synthesized from your own GitHub activity.',
                'redirect_url': f'http://localhost:{PORT}/github/callback',
                'callback_urls': [public + '/connect/callback'],
                'setup_url': public + '/connect/install',
                'request_oauth_on_install': False,
                'hook_attributes': {'url': public + '/api/github/webhook', 'active': True},
                'default_permissions': {'contents': 'read', 'pull_requests': 'read', 'issues': 'read'},
                # GitHub delivers installation/repository-access/authorization
                # lifecycle events automatically; they are not manifest options.
                'default_events': ['push', 'pull_request', 'issues'],
            }
            value = html.escape(json.dumps(manifest), quote=True)
            action = 'https://github.com/settings/apps/new?' + urlencode({'state': STATE})
            return self.respond(f'<h1>Create Shiplog on GitHub</h1><p>Read-only contents, pull requests, issues; explicit repository installation selection.</p><form method="post" action="{action}"><input type="hidden" name="manifest" value="{value}"><button>Create GitHub App</button></form>')
        if parsed.path == '/openrouter':
            if env.get('OPENROUTER_API_KEY'):
                return self.respond('OpenRouter credentials already configured. No duplicate created.')
            challenge = base64.urlsafe_b64encode(hashlib.sha256(VERIFIER.encode()).digest()).decode().rstrip('=')
            url = 'https://openrouter.ai/auth?' + urlencode({
                'callback_url': f'http://localhost:{PORT}/openrouter/callback',
                'code_challenge': challenge, 'code_challenge_method': 'S256',
                'state': STATE, 'key_label': 'Shiplog production',
            })
            self.send_response(302)
            self.send_header('Location', url)
            self.end_headers()
            return
        provider = parsed.path.split('/')[1]
        if parsed.path not in ('/github/callback', '/openrouter/callback'):
            return self.respond('Not found.', 404)
        if query.get('state', [''])[0] != STATE or not query.get('code') or provider in CONSUMED:
            return self.respond('Invalid or consumed setup callback.', 403)
        try:
            code = query['code'][0]
            if provider == 'github':
                if env.get('GITHUB_APP_ID'):
                    return self.respond('Existing credentials preserved.', 409)
                result = exchange('https://api.github.com/app-manifests/' + code + '/conversions')
                save_env({
                    'GITHUB_APP_ID': result['id'], 'GITHUB_APP_SLUG': result['slug'],
                    'GITHUB_CLIENT_ID': result['client_id'], 'GITHUB_CLIENT_SECRET': result['client_secret'],
                    'GITHUB_PRIVATE_KEY': result['pem'], 'GITHUB_WEBHOOK_SECRET': result['webhook_secret'],
                })
            else:
                if env.get('OPENROUTER_API_KEY'):
                    return self.respond('Existing credentials preserved.', 409)
                result = exchange('https://openrouter.ai/api/v1/auth/keys', {
                    'code': code, 'code_verifier': VERIFIER, 'code_challenge_method': 'S256',
                })
                save_env({'OPENROUTER_API_KEY': result['key']})
            CONSUMED.add(provider)
            print(provider + ' credentials saved securely.', flush=True)
            self.respond('Credentials saved securely. You may close this tab. <a href="/">Back</a>')
        except Exception as error:
            print(provider + ' exchange failed: ' + type(error).__name__, flush=True)
            self.respond('Credential exchange failed. No secret details printed; restart the setup flow.', 502)


if __name__ == '__main__':
    env = read_env()
    additions = {}
    for name in ['TOKEN_ENCRYPTION_KEY', 'CRON_SECRET']:
        if not env.get(name):
            additions[name] = base64.b64encode(secrets.token_bytes(32)).decode() if name == 'TOKEN_ENCRYPTION_KEY' else secrets.token_urlsafe(32)
    if additions:
        save_env(additions)
    print(f'Local credential setup: http://localhost:{PORT}', flush=True)
    HTTPServer(('127.0.0.1', PORT), Handler).serve_forever()

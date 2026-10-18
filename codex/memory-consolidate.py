#!/usr/bin/env python3
"""Run memory maintenance on a local app-server kept alive until consolidation finishes."""
import argparse
import datetime
import json
import contextlib
import queue
import shutil
import threading
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time


def log(message):
    print(f'{datetime.datetime.now().astimezone().isoformat(timespec="seconds")} {message}', flush=True)


def read_job(home):
    db = home / 'memories_1.sqlite'
    if not db.exists():
        raise RuntimeError(f'Memory database not found: {db}')
    with sqlite3.connect(f'{db.as_uri()}?mode=ro', uri=True, timeout=10) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute("SELECT * FROM jobs WHERE kind='memory_consolidate_global' AND job_key='global'").fetchone()
        return dict(row) if row else None


def retry_cancelled(home, work):
    """Release only a failed worker's retry delay; never take an active lease."""
    job = read_job(home)
    if not job or job['status'] != 'error' or job['last_error'] != 'failed_agent':
        return False
    stamp = time.time_ns()
    backup = work / f'memories-before-retry-{stamp}.sqlite'
    with sqlite3.connect(f'{(home / "memories_1.sqlite").as_uri()}?mode=ro', uri=True) as src:
        with sqlite3.connect(backup) as dst:
            src.backup(dst)
    backup.chmod(0o600)
    with sqlite3.connect(home / 'memories_1.sqlite', timeout=10) as conn:
        result = conn.execute("""UPDATE jobs SET retry_at=0, retry_remaining=MAX(retry_remaining, 1)
            WHERE kind='memory_consolidate_global' AND job_key='global'
            AND status='error' AND last_error='failed_agent' AND ownership_token IS ?""",
            (job['ownership_token'],))
    return result.rowcount == 1


def codex_command(executable):
    """Use a native CLI or invoke the official npm entry point directly."""
    parts = executable if isinstance(executable, (list, tuple)) else [executable]
    executable = Path(parts[0])
    extra = [str(arg) for arg in parts[1:]]
    if executable.suffix.lower() in ('.cmd', '.bat'):
        entry = executable.parent / 'node_modules/@openai/codex/bin/codex.js'
        node = shutil.which('node')
        if not node or not entry.is_file():
            raise RuntimeError('Use a native Codex executable or the official npm installation')
        return [node, str(entry), *extra]
    return [str(executable), *extra]


def default_codex():
    found = shutil.which('codex')
    if found:
        return found
    name = 'codex.exe' if os.name == 'nt' else 'codex'
    return str(Path.home() / '.local/bin' / name)


def acquire_lock(work):
    # SQLite's OS-level locks are released even if this process crashes.
    connection = sqlite3.connect(work / 'runner.lock.sqlite', timeout=0, isolation_level=None)
    try:
        connection.execute('BEGIN EXCLUSIVE')
    except sqlite3.OperationalError as exc:
        connection.close()
        if 'locked' in str(exc).lower():
            return None
        raise
    return connection


class Server:
    def __init__(self, executable, home):
        env = os.environ.copy()
        env['CODEX_HOME'] = str(home)
        self.stderr = (home / 'memory-maintenance/server.stderr.log').open('a', encoding='utf-8')
        try:
            self.process = subprocess.Popen(
                codex_command(executable) + ['app-server', '--listen', 'stdio://'],
                env=env, cwd=home / 'memory-maintenance', stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=self.stderr, text=True,
                encoding='utf-8', bufsize=1,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        except BaseException:
            self.stderr.close()
            raise
        self.messages = queue.Queue()
        self.next_id = 0
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.request('initialize', {'clientInfo': {'name': 'memory-maintenance', 'version': '2.0'},
                                       'capabilities': {'experimentalApi': True}})
            self.send({'method': 'initialized'})
        except BaseException:
            self.close()
            raise

    def _read(self):
        try:
            for line in self.process.stdout:
                self.messages.put(json.loads(line))
        except (ValueError, OSError) as exc:
            self.messages.put({'transport_error': str(exc)})
        finally:
            self.messages.put(None)

    def send(self, value):
        self.process.stdin.write(json.dumps(value) + '\n')
        self.process.stdin.flush()

    def _check(self, message):
        if message is None:
            raise RuntimeError(f'Maintenance app-server exited: {self.process.poll()}')
        if 'transport_error' in message:
            raise RuntimeError(f'Maintenance protocol failed: {message["transport_error"]}')

    def request(self, method, params):
        self.next_id += 1
        request_id = self.next_id
        self.send({'id': request_id, 'method': method, 'params': params})
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            try:
                message = self.messages.get(timeout=max(.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            self._check(message)
            if message.get('id') == request_id:
                if 'error' in message:
                    raise RuntimeError(f'{method}: {message["error"]}')
                return message['result']
        raise TimeoutError(f'App-server did not respond to {method}')

    def drain(self):
        for _ in range(100):
            try:
                message = self.messages.get_nowait()
            except queue.Empty:
                return
            self._check(message)

    def close(self):
        # The caller waits for the worker before closing its owning server.
        self.process.stdin.close()
        try:
            self.process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            log('App-server is still finishing graceful shutdown')
        if self.process.poll() is not None:
            self.reader.join(timeout=2)
            self.process.stdout.close()
        self.stderr.close()


def run(args):
    home = args.home.expanduser().resolve()
    work = home / 'memory-maintenance'
    work.mkdir(mode=0o700, exist_ok=True)
    lock = acquire_lock(work)
    if lock is None:
        log('Another maintenance runner is active; skipping')
        return 0
    try:
        return run_locked(args, home, work)
    finally:
        lock.close()


def run_locked(args, home, work):
    initial = read_job(home)
    if args.retry_cancelled and retry_cancelled(home, work):
        log('Re-enabled retry for cancelled consolidation; database snapshot saved')
        initial = read_job(home)
    if initial and initial['status'] == 'error':
        if initial['retry_remaining'] <= 0:
            raise RuntimeError(f'Consolidation retries exhausted: {initial["last_error"]}')
        if (initial['retry_at'] or 0) > time.time():
            log('Consolidation is in retry backoff; next scheduled run will retry')
            return 0
    server = None
    thread_id = None
    start = int(time.time())
    deadline = time.monotonic() + args.timeout
    try:
        active = initial and initial['status'] == 'running' and (initial['lease_until'] or 0) > time.time()
        if not active:
            server = Server(args.codex, home)
            thread = server.request('thread/start', {
                'cwd': str(work), 'approvalPolicy': 'never', 'sandbox': 'workspace-write',
                'threadSource': 'memory-maintenance',
                'config': {'memories.max_rollouts_per_startup': 1}})
            thread_id = thread['thread']['id']
            server.request('turn/start', {'threadId': thread_id,
                'input': [{'type': 'text', 'text': 'Reply OK. Do not use tools or perform any other actions.'}]})
            log(f'Maintenance session started on dedicated app-server: {thread_id}')
        else:
            log('Waiting for the existing consolidation worker')
        last = None
        while time.monotonic() < deadline:
            if server:
                server.drain()
            job = read_job(home)
            status = (job['status'], job['started_at'], job['last_error']) if job else None
            if status != last:
                log(f'Consolidation state: {status}')
                last = status
            current = job and (active or job['worker_id'] == thread_id or (job['started_at'] or 0) >= start)
            if current and job['status'] == 'done':
                log(f'Consolidation completed successfully; watermark={job["last_success_watermark"]}')
                if server and thread_id:
                    # Archive only this runner's session, after consolidation has finished.
                    server.request('thread/archive', {'threadId': thread_id})
                return 0
            if current and job['status'] == 'error':
                raise RuntimeError(f'Consolidation failed: {job["last_error"]}; retries={job["retry_remaining"]}')
            time.sleep(args.poll)
        raise TimeoutError('Consolidation timed out; shutting down the maintenance app-server')
    finally:
        if server:
            server.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path(os.environ.get('CODEX_HOME', '~/.codex')))
    parser.add_argument('--codex', nargs='+', default=[default_codex()], help='Codex executable and optional wrapper arguments')
    parser.add_argument('--retry-cancelled', action='store_true', help='Retry failed_agent immediately, with a database snapshot')
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('--poll', type=float, default=2)
    parser.add_argument('--log-file', type=Path)
    args = parser.parse_args()
    if args.timeout <= 0 or args.poll <= 0:
        parser.error('--timeout and --poll must be positive')
    with contextlib.ExitStack() as stack:
        if args.log_file:
            args.log_file.parent.mkdir(parents=True, exist_ok=True)
            output = stack.enter_context(args.log_file.open('a', encoding='utf-8', buffering=1))
            stack.enter_context(contextlib.redirect_stdout(output))
            stack.enter_context(contextlib.redirect_stderr(output))
        try:
            return run(args)
        except Exception as exc:
            log(f'ERROR: {exc}')
            return 1


if __name__ == '__main__':
    sys.exit(main())

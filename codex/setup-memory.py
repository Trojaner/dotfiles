#!/usr/bin/env python3
"""Install per-user memory maintenance using the native platform scheduler."""
import argparse
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

LABEL = 'com.esozbek.codex-memory-consolidation'
UNIT = 'codex-memory-consolidation'
TASK = 'CodexMemoryConsolidation'


def backup(path, runtime):
    directory = Path(tempfile.mkdtemp(prefix='dotfiles-backup.', dir=str(runtime)))
    if path.is_symlink():
        shutil.move(str(path), str(directory / path.name))
    else:
        shutil.copy2(path, directory / path.name)
    print(f'Backed up {path} to {directory}')


def write_changed(path, content, runtime, mode=0o600):
    if path.is_file() and not path.is_symlink() and path.read_bytes() == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() or path.is_symlink():
        backup(path, runtime)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(content)
    temporary.chmod(mode)
    os.replace(temporary, path)
    return True


def install_runner(source, target, runtime, system):
    target.parent.mkdir(parents=True, exist_ok=True)
    if system == 'Windows':
        write_changed(target, source.read_bytes(), runtime)
    elif not (target.is_symlink() and target.resolve() == source.resolve()):
        if target.exists() or target.is_symlink():
            backup(target, runtime)
        temporary = target.with_name(target.name + '.tmp')
        temporary.symlink_to(source.resolve())
        os.replace(temporary, target)


def systemd_quote(value):
    if '\n' in value or '\r' in value:
        raise ValueError('Scheduler paths cannot contain newlines')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%').replace('$', '$$') + '"'


def linux_units(command, runtime):
    directory = systemd_quote(str(runtime)).replace('$$', '$')
    environment = systemd_quote('PATH=' + os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin')).replace('$$', '$')
    service = ('[Unit]\nDescription=Consolidate Codex memories\n\n[Service]\nType=oneshot\n'
               f'WorkingDirectory={directory}\nEnvironment={environment}\n'
               f'ExecStart={" ".join(systemd_quote(str(arg)) for arg in command)}\n'
               'TimeoutStartSec=0\nUMask=0077\n')
    timer = ('[Unit]\nDescription=Run Codex memory consolidation hourly\n\n[Timer]\n'
             f'OnStartupSec=2min\nOnCalendar=hourly\nPersistent=true\nUnit={UNIT}.service\n\n'
             '[Install]\nWantedBy=timers.target\n')
    return service.encode(), timer.encode()


def windows_task(command, runtime, sid):
    namespace = 'http://schemas.microsoft.com/windows/2004/02/mit/task'
    ET.register_namespace('', namespace)
    def add(parent, name, text=None, **attrs):
        node = ET.SubElement(parent, '{'+namespace+'}'+name, attrs)
        node.text = text
        return node
    task = ET.Element('{'+namespace+'}Task', {'version': '1.3'})
    registration = add(task, 'RegistrationInfo')
    add(registration, 'Description', 'Consolidate Codex memories hourly and after login')
    triggers = add(task, 'Triggers')
    calendar = add(triggers, 'CalendarTrigger')
    add(calendar, 'Enabled', 'true')
    add(calendar, 'StartBoundary', '2020-01-01T00:00:00')
    repeat = add(calendar, 'Repetition')
    add(repeat, 'Interval', 'PT1H'); add(repeat, 'Duration', 'P1D')
    add(repeat, 'StopAtDurationEnd', 'false')
    add(add(calendar, 'ScheduleByDay'), 'DaysInterval', '1')
    login = add(triggers, 'LogonTrigger')
    add(login, 'Enabled', 'true'); add(login, 'UserId', sid); add(login, 'Delay', 'PT1M')
    principals = add(task, 'Principals')
    principal = add(principals, 'Principal', id='Author')
    add(principal, 'UserId', sid); add(principal, 'LogonType', 'InteractiveToken')
    add(principal, 'RunLevel', 'LeastPrivilege')
    settings = add(task, 'Settings')
    for key, value in [('MultipleInstancesPolicy', 'IgnoreNew'),
                       ('DisallowStartIfOnBatteries', 'false'), ('StopIfGoingOnBatteries', 'false'),
                       ('AllowHardTerminate', 'false'), ('StartWhenAvailable', 'true'),
                       ('Enabled', 'true'), ('ExecutionTimeLimit', 'PT0S')]:
        add(settings, key, value)
    action = add(add(task, 'Actions', Context='Author'), 'Exec')
    add(action, 'Command', str(command[0]))
    add(action, 'Arguments', subprocess.list2cmdline([str(arg) for arg in command[1:]]))
    add(action, 'WorkingDirectory', str(runtime))
    return ET.tostring(task, encoding='utf-16', xml_declaration=True)


def install(args, system=None, invoke=subprocess.run):
    system = system or platform.system()
    if system not in ('Darwin', 'Linux', 'Windows'):
        raise RuntimeError(f'Unsupported scheduler platform: {system}')
    home = args.home.expanduser().resolve()
    codex_home = args.codex_home.expanduser().resolve()
    runtime = codex_home / 'memory-maintenance'
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    python = args.python.expanduser().absolute()
    source = Path(__file__).resolve().with_name('memory-consolidate.py')
    target = home / '.local/bin/codex-memory-consolidate.py'
    # A scheduled task cannot rely on interactive shell aliases or PATH setup.
    codex = args.codex or shutil.which('codex')
    if not codex:
        for name in ('codex.exe', 'codex'):
            candidate = home / '.local/bin' / name
            if candidate.is_file():
                codex = str(candidate)
                break
    if not codex:
        raise RuntimeError('Install Codex and sign in before installing memory maintenance')
    if system == 'Linux':
        invoke(['systemctl', '--user', 'show-environment'], check=True, capture_output=True)
    install_runner(source, target, runtime, system)
    if system == 'Darwin':
        logs = home / 'Library/Logs/codex-memory-consolidation'
    elif system == 'Windows':
        logs = Path(os.environ.get('LOCALAPPDATA', str(home / 'AppData/Local'))) / 'CodexMemoryConsolidation/logs'
    else:
        logs = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state'))) / UNIT
    logs.mkdir(mode=0o700, parents=True, exist_ok=True)
    command = [str(python), str(target), '--home', str(codex_home), '--codex', str(codex),
               '--retry-cancelled', '--log-file', str(logs / 'runner.log')]
    if system == 'Darwin':
        template = Path(__file__).with_name('memory-consolidation.plist')
        content = plistlib.loads(template.read_bytes())
        content.update(ProgramArguments=command, WorkingDirectory=str(home),
                       StandardOutPath=str(logs/'runner.log'), StandardErrorPath=str(logs/'error.log'))
        content['EnvironmentVariables']['PATH'] = os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin')
        path = home / 'Library/LaunchAgents' / (LABEL+'.plist')
        write_changed(path, plistlib.dumps(content), runtime)
        domain = f'gui/{os.getuid()}'
        loaded = invoke(['launchctl', 'print', f'{domain}/{LABEL}'], capture_output=True)
        if loaded.returncode:
            invoke(['launchctl', 'bootstrap', domain, str(path)], check=True)
        else:
            print('LaunchAgent already loaded; new settings apply on next login')
    elif system == 'Linux':
        units = Path(os.environ.get('XDG_CONFIG_HOME', str(home/'.config'))) / 'systemd/user'
        service, timer = linux_units(command, runtime)
        write_changed(units/(UNIT+'.service'), service, runtime)
        write_changed(units/(UNIT+'.timer'), timer, runtime)
        invoke(['systemctl', '--user', 'daemon-reload'], check=True)
        invoke(['systemctl', '--user', 'enable', '--now', UNIT+'.timer'], check=True)
    else:
        identity = invoke(['whoami.exe', '/user', '/fo', 'csv', '/nh'], check=True, capture_output=True)
        match = re.search(rb'S-1-[0-9-]+', identity.stdout)
        if not match:
            raise RuntimeError('Cannot determine the current Windows user SID')
        path = runtime / 'scheduled-task.xml'
        content = windows_task(command, runtime, match.group().decode('ascii'))
        write_changed(path, content, runtime)
        previous = invoke(['schtasks.exe', '/Query', '/TN', TASK, '/XML'], capture_output=True)
        if previous.returncode == 0:
            directory = Path(tempfile.mkdtemp(prefix='dotfiles-backup.', dir=str(runtime)))
            (directory/'previous-task.xml').write_bytes(previous.stdout)
        invoke(['schtasks.exe', '/Create', '/TN', TASK, '/XML', str(path), '/F'], check=True)
    print(f'Hourly memory consolidation installed on {system}; logs: {logs}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--codex-home', type=Path, default=Path(os.environ.get('CODEX_HOME', '~/.codex')))
    parser.add_argument('--python', type=Path, default=Path(sys.executable))
    parser.add_argument('--codex')
    args = parser.parse_args()
    try:
        install(args)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Memory maintenance installation failed: {exc}\n')


if __name__ == '__main__':
    main()

import argparse
import contextlib
import io
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parent

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

runner = load('runner', Path(os.environ.get('CODEX_MEMORY_RUNNER', BASE/'memory-consolidate.py')))
installer = load('installer', BASE/'setup-memory.py')

class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cmr-')
        self.home = Path(self.temp.name).resolve()
        self.db = self.home/'memories_1.sqlite'
        with sqlite3.connect(self.db) as c:
            c.execute('''CREATE TABLE jobs (kind TEXT,job_key TEXT,status TEXT,worker_id TEXT,
                ownership_token TEXT,started_at INTEGER,finished_at INTEGER,lease_until INTEGER,
                retry_at INTEGER,retry_remaining INTEGER,last_error TEXT,input_watermark INTEGER,
                last_success_watermark INTEGER)''')
            c.execute("INSERT INTO jobs VALUES ('memory_consolidate_global','global','error','old','token',1,2,NULL,9999999999,0,'failed_agent',42,7)")
    def tearDown(self):
        self.temp.cleanup()
    def test_retry_preserves_inputs_and_does_not_claim_running_job(self):
        work = self.home/'maintenance';work.mkdir()
        self.assertTrue(runner.retry_cancelled(self.home,work))
        job = runner.read_job(self.home)
        self.assertEqual((job['status'],job['input_watermark'],job['last_success_watermark']),('error',42,7))
        self.assertEqual((job['retry_at'],job['retry_remaining']),(0,1))
        with sqlite3.connect(next(work.glob('memories-before-retry-*.sqlite'))) as c:
            self.assertEqual(c.execute('SELECT retry_at FROM jobs').fetchone()[0],9999999999)
        with sqlite3.connect(self.db) as c:c.execute("UPDATE jobs SET status='running',lease_until=9999999999")
        self.assertFalse(runner.retry_cancelled(self.home,work))
    def test_other_errors_are_not_reset(self):
        with sqlite3.connect(self.db) as c:c.execute("UPDATE jobs SET last_error='failed_invalid_artifacts'")
        self.assertFalse(runner.retry_cancelled(self.home,self.home))
        self.assertEqual(runner.read_job(self.home)['retry_at'],9999999999)
    def test_lock_excludes_another_process_and_releases_cleanly(self):
        work = self.home/'memory-maintenance';work.mkdir()
        lock = runner.acquire_lock(work)
        command = [sys.executable,'-B','-c',
            'import importlib.util,sys;from pathlib import Path;'
            's=importlib.util.spec_from_file_location("r",sys.argv[1]);'
            'r=importlib.util.module_from_spec(s);s.loader.exec_module(r);'
            'lock=r.acquire_lock(Path(sys.argv[2]));sys.exit(0 if lock is None else 5)',
            str(BASE/'memory-consolidate.py'),str(work)]
        try:self.assertEqual(subprocess.run(command).returncode,0)
        finally:lock.close()
        again=runner.acquire_lock(work);self.assertIsNotNone(again);again.close()
    def test_runner_keeps_server_alive_after_root_turn_finishes(self):
        fake = self.home/'fake_server.py'
        fake.write_text(textwrap.dedent('''
            import os,sys,json,sqlite3,time,threading
            from pathlib import Path
            home=Path(os.environ['CODEX_HOME'])
            def reply(i,result):print(json.dumps({'id':i,'result':result}),flush=True)
            def finish():
                time.sleep(.5)
                with sqlite3.connect(home/'memories_1.sqlite') as c:
                    c.execute("UPDATE jobs SET status='done',finished_at=?,last_success_watermark=input_watermark,last_error=NULL",(int(time.time()),))
                (home/'worker-finished').touch()
            for line in sys.stdin:
                d=json.loads(line);method=d['method']
                if method=='initialize':reply(d['id'],{})
                elif method=='thread/start':reply(d['id'],{'thread':{'id':'maintenance-test'}})
                elif method=='turn/start':
                    with sqlite3.connect(home/'memories_1.sqlite') as c:
                        c.execute("UPDATE jobs SET status='running',worker_id='maintenance-test',started_at=?,last_error=NULL",(int(time.time()),))
                    reply(d['id'],{'turn':{'status':'completed'}})
                    threading.Thread(target=finish,daemon=True).start()
                elif method=='thread/archive':
                    if not (home/'worker-finished').exists():sys.exit(8)
                    (home/'archived-after-worker').touch();reply(d['id'],{})
            if not (home/'worker-finished').exists():sys.exit(9)
        '''),encoding='utf-8')
        result=subprocess.run([sys.executable,str(BASE/'memory-consolidate.py'),'--home',str(self.home),
            '--codex',sys.executable,str(fake),'--retry-cancelled','--poll','0.05','--timeout','10'],
            capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue((self.home/'archived-after-worker').exists())
        self.assertEqual(runner.read_job(self.home)['last_success_watermark'],42)
    def test_official_windows_npm_shim_uses_node_without_shell(self):
        shim=self.home/'codex.cmd';entry=self.home/'node_modules/@openai/codex/bin/codex.js'
        entry.parent.mkdir(parents=True);entry.touch()
        with mock.patch.object(runner.shutil,'which',return_value='node.exe'):
            self.assertEqual(runner.codex_command(shim),['node.exe',str(entry)])

class SchedulerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='cms-')
        self.home=Path(self.temp.name).resolve()/'home & 50% $value spaces'
        self.home.mkdir()
        self.args=argparse.Namespace(home=self.home,codex_home=self.home/'custom state',
            python=Path(sys.executable),codex=str(self.home/'codex executable'))
        self.calls=[];self.loaded=False;self.registered=False
        self.env=mock.patch.dict(os.environ,{
            'XDG_CONFIG_HOME':str(self.home/'.config'),
            'XDG_STATE_HOME':str(self.home/'.local/state'),
            'LOCALAPPDATA':str(self.home/'AppData/Local')})
        self.env.start()
    def tearDown(self):
        self.env.stop();self.temp.cleanup()
    def invoke(self,cmd,**kwargs):
        self.calls.append(cmd)
        if cmd[:2]==['launchctl','print']:
            return subprocess.CompletedProcess(cmd,0 if self.loaded else 1)
        if cmd[:2]==['launchctl','bootstrap']:self.loaded=True
        if cmd[0]=='whoami.exe':
            return subprocess.CompletedProcess(cmd,0,b'"user","S-1-5-21-123-456-789-1001"\r\n')
        if cmd[:2]==['schtasks.exe','/Query']:
            return subprocess.CompletedProcess(cmd,0 if self.registered else 1,b'<previous-task/>')
        if cmd[:2]==['schtasks.exe','/Create']:self.registered=True
        return subprocess.CompletedProcess(cmd,0)
    def run_twice(self,system):
        target=self.home/'.local/bin/codex-memory-consolidate.py'
        target.parent.mkdir(parents=True);target.write_text('original runner')
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(self.args,system,self.invoke)
            installer.install(self.args,system,self.invoke)
        runtime=self.args.codex_home/'memory-maintenance'
        copies=list(runtime.glob('dotfiles-backup.*/codex-memory-consolidate.py'))
        self.assertEqual(len(copies),1)
        self.assertEqual(copies[0].read_text(),'original runner')
        return target,runtime
    @unittest.skipUnless(hasattr(os,'getuid'),'launchd is Unix-specific')
    def test_macos_installer_preserves_runner_and_bootstraps_once(self):
        import plistlib
        target,runtime=self.run_twice('Darwin')
        self.assertEqual(target.resolve(),(BASE/'memory-consolidate.py').resolve())
        plist=plistlib.loads((self.home/'Library/LaunchAgents'/f'{installer.LABEL}.plist').read_bytes())
        self.assertEqual(plist['ProgramArguments'][0],str(self.args.python.absolute()))
        self.assertIn(str(self.args.codex_home),plist['ProgramArguments'])
        self.assertNotIn('@HOME@',str(plist))
        self.assertEqual(sum(c[:2]==['launchctl','bootstrap'] for c in self.calls),1)
    @unittest.skipIf(os.name == 'nt', 'Linux installer uses Unix symlinks')
    def test_linux_installer_enables_user_timer_and_preserves_paths(self):
        target,runtime=self.run_twice('Linux')
        service=(self.home/'.config/systemd/user'/f'{installer.UNIT}.service').read_text()
        timer=(self.home/'.config/systemd/user'/f'{installer.UNIT}.timer').read_text()
        self.assertIn('50%% $$value spaces',service)
        self.assertIn('Environment="PATH=',service)
        self.assertIn('OnCalendar=hourly',timer)
        self.assertIn(['systemctl','--user','enable','--now',installer.UNIT+'.timer'],self.calls)
    def test_windows_installer_copies_without_symlinks_and_uses_current_user(self):
        target,runtime=self.run_twice('Windows')
        self.assertFalse(target.is_symlink())
        self.assertEqual(target.read_bytes(),(BASE/'memory-consolidate.py').read_bytes())
        xml=ET.fromstring((runtime/'scheduled-task.xml').read_bytes())
        ns={'t':'http://schemas.microsoft.com/windows/2004/02/mit/task'}
        self.assertEqual(xml.findtext('.//t:LogonType',namespaces=ns),'InteractiveToken')
        self.assertEqual(xml.findtext('.//t:RunLevel',namespaces=ns),'LeastPrivilege')
        self.assertEqual(xml.findtext('.//t:Interval',namespaces=ns),'PT1H')
        self.assertEqual(xml.findtext('.//t:Command',namespaces=ns),str(self.args.python.absolute()))
        args=xml.findtext('.//t:Arguments',namespaces=ns)
        self.assertIn('"'+str(self.args.codex_home)+'"',args)
        self.assertEqual(xml.findtext('.//t:WorkingDirectory',namespaces=ns),str(runtime))
        self.assertTrue(list(runtime.glob('dotfiles-backup.*/previous-task.xml')))

if __name__=='__main__':unittest.main()

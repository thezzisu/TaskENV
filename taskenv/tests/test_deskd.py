#!/usr/bin/python3
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

loader=importlib.machinery.SourceFileLoader('deskd', str(Path(__file__).resolve().parents[1]/'deskd/deskd'))
spec=importlib.util.spec_from_loader(loader.name,loader)
deskd=importlib.util.module_from_spec(spec);loader.exec_module(deskd)

class ConnectionContract(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home=Path(self.directory.name)
        self.credentials=self.home/'.config/deskd/credentials.json'
        self.credentials.parent.mkdir(parents=True)
        self.credentials.write_text(json.dumps({'username':'ubuntu','password':'private-password'}))
        for target,attr,value in [(deskd.Path,'home',self.home),(deskd.os,'getuid',1000),(deskd,'status',{'ready':True})]:
            mocked=patch.object(target,attr,return_value=value);mocked.start();self.addCleanup(mocked.stop)

    def test_reports_own_endpoint_and_authentication(self):
        self.assertEqual(deskd.connect_info(), {'version':1,'port':6900,'authentication':{'scheme':'basic','username':'ubuntu','password':'private-password'}})
        with patch.object(deskd,'PORT',7900):
            self.assertEqual(deskd.connect_info()['port'],7900)

    def test_unready_desktop_does_not_disclose_credentials(self):
        with patch.object(deskd,'status',return_value={'ready':False}):
            with self.assertRaisesRegex(RuntimeError,'desktop is not ready'):
                deskd.connect_info()

    def test_missing_or_malformed_credentials_fail_without_secret_output(self):
        for value in ['broken-private-password', '{"username":"ubuntu","password":123}', '{"username":"bad:user","password":"private-password"}']:
            self.credentials.write_text(value)
            with self.assertRaisesRegex(RuntimeError,'desktop authentication is unavailable'):
                deskd.connect_info()
        self.credentials.unlink()
        with self.assertRaisesRegex(RuntimeError,'desktop authentication is unavailable'):
            deskd.connect_info()

    def test_terminal_rejects_private_output_and_pipe_emits_only_json(self):
        for interactive in (True,False):
            output,error=io.StringIO(),io.StringIO()
            with contextlib.redirect_stdout(output),contextlib.redirect_stderr(error),patch.object(output,'isatty',return_value=interactive),patch('sys.argv',['deskd','connect-info']):
                code=deskd.main()
            if interactive:
                self.assertEqual(code,1);self.assertEqual(output.getvalue(),'')
                self.assertNotIn('private-password',error.getvalue())
            else:
                self.assertEqual(code,0);self.assertEqual(error.getvalue(),'')
                self.assertEqual(json.loads(output.getvalue())['authentication']['scheme'],'basic')

if __name__=='__main__':unittest.main()

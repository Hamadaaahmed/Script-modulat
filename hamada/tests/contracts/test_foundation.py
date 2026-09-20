import io, json, tempfile, unittest
from pathlib import Path
from hamada.core.registry import ModuleRegistry
from hamada.core.validation import validate_manifest, validate_directory
from hamada.core.output import emit

ROOT=Path(__file__).resolve().parents[2]
MANIFESTS=ROOT/'manifests'

def base(mid='alpha'):
 return {'schema_version':1,'id':mid,'name':mid,'version':'1','description':'test','dependencies':{'modules':[],'optional_modules':[],'infrastructure':[]},'conflicts':{'modules':[],'notes':[]},'requirements':{'packages':[],'binaries':[],'certificate':False,'edge':False},'paths':{'config':[],'data':[],'legacy':[]},'services':[],'ports':{'public_tcp':[],'public_udp':[],'internal_tcp':[],'internal_udp':[]},'firewall':{'ownership':'none','requirements':[]},'edge':{'ownership':'none','routes':[],'backends':[]},'accounts':{'supported':False,'backend':None,'capabilities':[]},'healthchecks':[],'lifecycle':[]}

def write(d,p): Path(p).write_text(json.dumps(d))

class FoundationTests(unittest.TestCase):
 def test_schema_document_is_machine_readable(self):
  schema=json.loads((ROOT/"schemas/module.schema.json").read_text())
  self.assertEqual("object",schema["type"]); self.assertIn("id",schema["properties"]); self.assertIn("ports",schema["properties"])
 def test_real_manifests_have_no_errors(self):
  reg, findings=validate_directory(MANIFESTS)
  self.assertGreaterEqual(len(reg.modules),10)
  self.assertEqual([], [f for f in findings if f.severity=='ERROR'])
 def test_invalid_manifest(self):
  self.assertTrue(validate_manifest({'id':'BAD ID'}))
 def test_duplicate_module_id(self):
  with tempfile.TemporaryDirectory() as d:
   write(base('same'),Path(d)/'a.json'); write(base('same'),Path(d)/'b.json')
   self.assertTrue(any(f.code=='DUPLICATE_MODULE_ID' for f in ModuleRegistry(d).load().findings))
 def test_duplicate_tcp_port(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); b=base('bb'); a['ports']['public_tcp']=[{'port':443,'purpose':'a'}]; b['ports']['public_tcp']=[{'port':443,'purpose':'b'}]
   write(a,Path(d)/'a.json'); write(b,Path(d)/'b.json')
   self.assertTrue(ModuleRegistry(d).load().port_findings())
 def test_duplicate_udp_port(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); b=base('bb'); a['ports']['public_udp']=[{'port':53,'purpose':'a'}]; b['ports']['public_udp']=[{'port':53,'purpose':'b'}]
   write(a,Path(d)/'a.json'); write(b,Path(d)/'b.json')
   self.assertTrue(ModuleRegistry(d).load().port_findings())
 def test_same_tcp_udp_number_allowed(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); b=base('bb'); a['ports']['public_tcp']=[{'port':443,'purpose':'a'}]; b['ports']['public_udp']=[{'port':443,'purpose':'b'}]
   write(a,Path(d)/'a.json'); write(b,Path(d)/'b.json')
   self.assertEqual([],ModuleRegistry(d).load().port_findings())
 def test_dependency_resolution(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); b=base('bb'); b['dependencies']['modules']=['aa']; write(a,Path(d)/'a.json'); write(b,Path(d)/'b.json')
   self.assertEqual([],ModuleRegistry(d).load().dependency_findings())
 def test_unknown_dependency(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); a['dependencies']['modules']=['missing']; write(a,Path(d)/'a.json')
   self.assertTrue(ModuleRegistry(d).load().dependency_findings())
 def test_dependency_cycle(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); b=base('bb'); a['dependencies']['modules']=['bb']; b['dependencies']['modules']=['aa']; write(a,Path(d)/'a.json'); write(b,Path(d)/'b.json')
   self.assertTrue(ModuleRegistry(d).load().dependency_cycles())
 def test_conflict_detection(self):
  with tempfile.TemporaryDirectory() as d:
   a=base('aa'); b=base('bb'); a['conflicts']['modules']=['bb']; write(a,Path(d)/'a.json'); write(b,Path(d)/'b.json')
   self.assertTrue(ModuleRegistry(d).load().conflict_findings())
 def test_path_validation(self):
  a=base('aa'); a['paths']['config']=['../bad']; self.assertTrue(any(f.code=='INVALID_PATH' for f in validate_manifest(a)))
 def test_logging(self):
  s=io.StringIO(); line=emit('INFO','hello',stream=s); self.assertEqual('[INFO] hello',line); self.assertEqual('[INFO] hello\n',s.getvalue())
 def test_debug_quiet_by_default(self):
  s=io.StringIO(); self.assertEqual('',emit('DEBUG','secret-ish diagnostic',stream=s)); self.assertEqual('',s.getvalue())

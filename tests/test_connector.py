import base64,hashlib,hmac,importlib.util,json,threading,time,unittest,urllib.request,urllib.error
from pathlib import Path

spec=importlib.util.spec_from_file_location('agent',Path(__file__).parents[1]/'connector/nucel_agent.py')
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)

class ConnectorTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  a.CONFIG.update(secret='test-only-secret'*5,allowed_origin='https://nucel.test',adb_path='adb')
  cls.calls=[];cls.commands=[]
  def fake(*args,**kwargs):
   cls.calls.append(args)
   if args==('devices',):return b'List of devices attached\nALLOWED\tdevice\nHIDDEN\tdevice\n'
   if 'wm' in args and 'size' in args:return b'Physical size: 1080x2400\n'
   return b''
  class Shell:
   def __init__(self,serial):self.serial=serial
   def send(self,command):cls.commands.append((self.serial,command))
  a.adb=fake
  a.control_shell=lambda serial:Shell(serial)
  cls.server=a.ThreadingHTTPServer(('127.0.0.1',0),a.Handler)
  cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()

 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close()

 def token(self,**kwargs):
  data={'exp':time.time()+60,'origin':'https://nucel.test','serials':['ALLOWED'],**kwargs}
  p=base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip('=')
  sig=base64.urlsafe_b64encode(hmac.new(a.CONFIG['secret'].encode(),p.encode(),hashlib.sha256).digest()).decode().rstrip('=')
  return p+'.'+sig

 def req(self,path,body=None,token=None,origin='https://nucel.test'):
  request=urllib.request.Request('http://127.0.0.1:'+str(self.server.server_port)+path,data=json.dumps(body).encode() if body else None,headers={'Origin':origin,'Authorization':'Bearer '+(token or self.token()),'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(request) as r:return r.status,r.read()
  except urllib.error.HTTPError as e:return e.code,e.read()

 def test_hidden_devices_not_disclosed(self):
  code,body=self.req('/status');self.assertEqual(code,200);self.assertEqual(json.loads(body),{'devices':{'ALLOWED':'device'}})

 def test_denied_serial(self):self.assertEqual(self.req('/video?serial=HIDDEN')[0],403)
 def test_tampered_token(self):self.assertEqual(self.req('/status',token=self.token()+'a')[0],401)
 def test_expired_token(self):self.assertEqual(self.req('/status',token=self.token(exp=time.time()-1))[0],401)
 def test_wrong_origin(self):self.assertEqual(self.req('/status',origin='https://other.test')[0],401)

 def test_tap_maps_full_resolution(self):
  code,_=self.req('/action',{'serial':'ALLOWED','type':'tap','x':.5,'y':.5});self.assertEqual(code,200)
  self.assertIn(('ALLOWED','input tap 540 1200'),self.commands)

 def test_invalid_coordinates(self):self.assertEqual(self.req('/action',{'serial':'ALLOWED','type':'tap','x':2,'y':.2})[0],400)
 def test_rejects_arbitrary_command(self):self.assertEqual(self.req('/action',{'serial':'ALLOWED','type':'shell','command':'reboot'})[0],400)
 def test_invalid_serial(self):self.assertEqual(self.req('/action',{'serial':'ALLOWED;reboot','type':'key','key':'home'})[0],403)

 def test_native_key(self):
  self.assertEqual(self.req('/action',{'serial':'ALLOWED','type':'key','key':'home'})[0],200)
  self.assertIn(('ALLOWED','input keyevent 3'),self.commands)

if __name__=='__main__':unittest.main()

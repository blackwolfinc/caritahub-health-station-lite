#!/usr/bin/env python3
"""QA round 3 - mock SATUSEHAT server exercising docs/satusehat_upload.py.
Run: python3 test/qa/r3_uploader_qa.py   (needs build/satusehat_samples from `flutter test test/satusehat_test.dart`)
"""
import json, os, subprocess, sys, tempfile, threading, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "docs", "satusehat_upload.py")
SAMPLE = os.path.join(ROOT, "build", "satusehat_samples", "sample.ndjson")
KNOWN = {"3201015203580001": "P02478375538"}
state = {"posts": [], "lookups": [], "drop_post_no": None}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        ident = urllib.parse.parse_qs(u.query).get("identifier", [""])[0]
        state["lookups"].append(ident)
        nik = ident.split("|")[-1]
        if nik in KNOWN:
            self._send(200, {"resourceType": "Bundle", "entry": [{"resource": {"resourceType": "Patient", "id": KNOWN[nik]}}]})
        else:
            self._send(200, {"resourceType": "Bundle", "total": 0, "entry": []})
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); body = self.rfile.read(n)
        if self.path.startswith("/oauth2"):
            return self._send(200, {"access_token": "T"})
        b = json.loads(body)
        state["posts"].append(b)
        if state["drop_post_no"] == len(state["posts"]):
            self.connection.close()  # network drop / gateway reset
            return
        enc = b["entry"][0]["resource"]
        assert enc["subject"]["reference"].startswith("Patient/"), enc["subject"]
        self._send(200, {"resourceType": "Bundle", "type": "transaction-response",
                         "entry": [{"response": {"status": "201 Created", "location": e["request"]["url"] + "/x"}} for e in b["entry"]]})

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"
env = dict(os.environ, SATUSEHAT_CLIENT_ID="x", SATUSEHAT_CLIENT_SECRET="y")

def run(path):
    return subprocess.run([sys.executable, "-I", SCRIPT, path, "--base-url", BASE], env=env,
                          capture_output=True, text=True, timeout=60)

lines = open(SAMPLE, encoding="utf-8").read().strip().splitlines()
tmp = tempfile.mkdtemp()

# 1) retry after partial failure re-posts already accepted bundles (duplicates in SATUSEHAT)
b_ok = json.loads(lines[0])
b_bad = json.loads(lines[1].replace("3201015203580001", "3578010711520002").replace('"C"', '"C2"'))
f1 = os.path.join(tmp, "batch.ndjson")
open(f1, "w").write(json.dumps(b_ok) + "\n" + json.dumps(b_bad) + "\n")
r1 = run(f1)
print("run1 rc=", r1.returncode, r1.stdout.strip().splitlines()[-1])
KNOWN["3578010711520002"] = "P0000002"  # patient registered, operator retries as the docstring suggests
r2 = run(f1)
ids = [p["entry"][0]["resource"]["identifier"][0]["value"] for p in state["posts"]]
print("run2 rc=", r2.returncode, "| encounter ids POSTed across both runs:", ids)
print("lookup identifier received by server:", state["lookups"][0])
print("RESULT duplicate POST of same Encounter:", ids.count(ids[0]) > 1)

# 2) network drop mid-batch: crash, .hasil.json never written although bundle 1 was accepted
state["posts"].clear(); state["drop_post_no"] = 2
f2 = os.path.join(tmp, "drop.ndjson")
open(f2, "w").write(json.dumps(b_ok) + "\n" + json.dumps(json.loads(lines[1])) + "\n")
r3 = run(f2)
print("drop run rc=", r3.returncode, "| last stderr line:", (r3.stderr.strip().splitlines() or [""])[-1][:120])
print("RESULT hasil.json written:", os.path.exists(f2 + ".hasil.json"), "| bundles accepted before crash: 1")
state["drop_post_no"] = None

# 3) single bundle file re-saved with UTF-8 BOM (Notepad / some share targets)
f3 = os.path.join(tmp, "one.json")
open(f3, "w", encoding="utf-8-sig").write(json.dumps(b_ok, indent=2))
r4 = run(f3)
print("BOM run rc=", r4.returncode, "| last stderr line:", (r4.stderr.strip().splitlines() or [""])[-1][:120])

# 4) pretty single bundle (app 'Hasil' export) is detected as single JSON
f4 = os.path.join(tmp, "pretty.json")
open(f4, "w").write(open(os.path.join(ROOT, "build", "satusehat_samples", "sample_bundle.json")).read())
r5 = subprocess.run([sys.executable, "-I", SCRIPT, f4, "--dry-run"], capture_output=True, text=True)
print("pretty dry-run:", r5.stdout.strip().replace("\n", " | "))
srv.shutdown()

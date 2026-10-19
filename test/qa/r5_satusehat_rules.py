#!/usr/bin/env python3
"""QA putaran 5 — aturan SATUSEHAT (dari dokumentasi resmi) untuk Bundle ekspor.

Memeriksa:
  * Bundle transaction: fullUrl urn:uuid unik, request POST ke tipe resource.
  * Encounter: status, statusHistory arrived→in-progress→finished, class AMB
    (v3-ActCode), participant ATND, period.start, location, serviceProvider,
    identifier http://sys-ids.kemkes.go.id/encounter/<org>, waktu ...+00:00,
    akhir >= awal.
  * Observation: status, category, kode LOINC + satuan UCUM sesuai tabel
    dokumentasi (Rawat Inap: tanda vital; Gizi: berat/tinggi/IMT), subject,
    encounter yang menunjuk Encounter di Bundle yang sama, effectiveDateTime.
  * Setelah pengirim mengganti NIK → IHS: subject = Patient/<id>.
  * Juga mengirim lewat docs/satusehat_upload.py ke server tiruan yang
    menolak payload yang melanggar aturan di atas.

Jalankan: python3 test/qa/r5_satusehat_rules.py build/satusehat_samples/*.json
          python3 test/qa/r5_satusehat_rules.py build/satusehat_samples/stress40.ndjson
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

TIME = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+00:00$")
UUID = re.compile(r"^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
LOINC = "http://loinc.org"
UCUM = "http://unitsofmeasure.org"

# kode → (kategori, unit, kode UCUM) — dokumentasi SATUSEHAT + LOINC.
EXPECTED = {
    "8480-6": ("vital-signs", "mm[Hg]", "mm[Hg]"),
    "8462-4": ("vital-signs", "mm[Hg]", "mm[Hg]"),
    "8867-4": ("vital-signs", "beats/min", "/min"),
    "8310-5": ("vital-signs", "C", "Cel"),
    "29463-7": ("vital-signs", "kg", "kg"),
    "8302-2": ("vital-signs", "cm", "cm"),
    "39156-5": ("exam", "kg/m2", "kg/m2"),
    "59408-5": ("vital-signs", "%", "%"),
    "41982-0": ("exam", "%", "%"),
    "83173-5": ("exam", "kgf", "kgf"),
    "83174-3": ("exam", "kgf", "kgf"),
}


def check_bundle(b, after_upload=False):
    errs = []
    def err(m):
        errs.append(m)

    if b.get("resourceType") != "Bundle" or b.get("type") != "transaction":
        err("bukan Bundle transaction")
    entries = b.get("entry") or []
    urls = [e.get("fullUrl") for e in entries]
    if len(set(urls)) != len(urls):
        err("fullUrl ganda")
    for e in entries:
        res = e.get("resource") or {}
        if not UUID.match(e.get("fullUrl", "")):
            err(f"fullUrl bukan urn:uuid v4: {e.get('fullUrl')}")
        req = e.get("request") or {}
        if req != {"method": "POST", "url": res.get("resourceType")}:
            err(f"request salah: {req}")
    encs = [e for e in entries if e["resource"]["resourceType"] == "Encounter"]
    if len(encs) != 1:
        err("harus tepat 1 Encounter")
        return errs
    enc_url = encs[0]["fullUrl"]
    enc = encs[0]["resource"]
    for k in ["status", "statusHistory", "class", "subject", "participant", "period",
              "location", "serviceProvider", "identifier"]:
        if k not in enc:
            err(f"Encounter tanpa {k}")
    if enc.get("class", {}).get("system") != "http://terminology.hl7.org/CodeSystem/v3-ActCode" \
            or enc.get("class", {}).get("code") != "AMB":
        err("Encounter.class bukan AMB v3-ActCode")
    sh = [h.get("status") for h in enc.get("statusHistory", [])]
    if sh != ["arrived", "in-progress", "finished"]:
        err(f"statusHistory {sh}")
    if enc.get("status") != sh[-1:][0] if sh else True:
        err("status tidak sama dengan statusHistory terakhir")
    p = enc.get("participant", [{}])[0]
    if p.get("type", [{}])[0].get("coding", [{}])[0].get("code") != "ATND":
        err("participant bukan ATND")
    if not re.match(r"^Practitioner/[A-Za-z0-9\-.]+$", p.get("individual", {}).get("reference", "")):
        err("participant.individual bukan Practitioner/<id>")
    if not re.match(r"^Location/[A-Za-z0-9\-.]+$", enc.get("location", [{}])[0].get("location", {}).get("reference", "")):
        err("location bukan Location/<id>")
    org = enc.get("serviceProvider", {}).get("reference", "")
    if not re.match(r"^Organization/[A-Za-z0-9\-.]+$", org):
        err("serviceProvider bukan Organization/<id>")
    ident = enc.get("identifier", [{}])[0]
    if ident.get("system") != "http://sys-ids.kemkes.go.id/encounter/" + org.split("/")[-1]:
        err(f"identifier.system {ident.get('system')}")
    times = [enc["period"].get("start"), enc["period"].get("end")]
    for h in enc.get("statusHistory", []):
        times += [h["period"].get("start"), h["period"].get("end")]
    for t in times:
        if not t or not TIME.match(t):
            err(f"format waktu {t}")
    if enc["period"]["end"] < enc["period"]["start"]:
        err("period.end < start")

    def subject_ok(s):
        if after_upload:
            return bool(re.match(r"^Patient/[A-Za-z0-9\-.]+$", s.get("reference", "")))
        idt = s.get("identifier", {})
        return idt.get("system") == "https://fhir.kemkes.go.id/id/nik" and re.match(r"^\d{16}$", idt.get("value", ""))

    if not subject_ok(enc.get("subject", {})):
        err(f"Encounter.subject {enc.get('subject')}")

    for e in entries:
        res = e["resource"]
        rt = res["resourceType"]
        if rt == "Condition":
            if res.get("encounter", {}).get("reference") != enc_url:
                err("Condition.encounter tidak ke Encounter")
            continue
        if rt != "Observation":
            continue
        for k in ["status", "category", "code", "subject", "encounter", "effectiveDateTime", "valueQuantity"]:
            if k not in res:
                err(f"Observation tanpa {k}")
        codes = [c["code"] for c in res["code"]["coding"] if c.get("system") == LOINC]
        if not codes:
            err("Observation tanpa kode LOINC")
            continue
        code = codes[0]
        exp = EXPECTED.get(code)
        if not exp:
            err(f"kode LOINC tak dikenal {code}")
            continue
        cat = res["category"][0]["coding"][0]
        if cat.get("system") != "http://terminology.hl7.org/CodeSystem/observation-category" or cat.get("code") != exp[0]:
            err(f"{code}: kategori {cat}")
        vq = res["valueQuantity"]
        if vq.get("system") != UCUM or vq.get("unit") != exp[1] or vq.get("code") != exp[2]:
            err(f"{code}: satuan {vq}")
        if not isinstance(vq.get("value"), (int, float)):
            err(f"{code}: nilai bukan angka")
        if res["encounter"].get("reference") != enc_url:
            err(f"{code}: encounter tidak menunjuk Encounter di Bundle")
        if not subject_ok(res.get("subject", {})):
            err(f"{code}: subject {res.get('subject')}")
        if not TIME.match(res.get("effectiveDateTime", "")):
            err(f"{code}: effectiveDateTime {res.get('effectiveDateTime')}")
    return errs


class Mock(BaseHTTPRequestHandler):
    posted = []
    rejected = []

    def log_message(self, *a):
        pass

    def _send(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        if self.path.startswith("/oauth2/v1/accesstoken"):
            return self._send(200, {"access_token": "tok", "expires_in": "3599"})
        if self.headers.get("Authorization") != "Bearer tok":
            return self._send(401, {"issue": [{"code": "login"}]})
        b = json.loads(body)
        errs = check_bundle(b, after_upload=True)
        if errs:
            Mock.rejected.append(errs)
            return self._send(400, {"resourceType": "OperationOutcome",
                                    "issue": [{"severity": "error", "diagnostics": m} for m in errs]})
        Mock.posted.append(b)
        return self._send(200, {"resourceType": "Bundle", "type": "transaction-response",
                                "entry": [{"response": {"status": "201 Created",
                                                        "resourceID": f"id-{i}"}}
                                          for i, _ in enumerate(b["entry"])]})

    def do_GET(self):
        if "Patient?identifier=" in self.path:
            return self._send(200, {"resourceType": "Bundle", "entry": [
                {"resource": {"resourceType": "Patient", "id": "P02478375538"}}]})
        return self._send(404, {})


def load_all(paths):
    """(nama, bundle) dari file .json (satu Bundle) atau .ndjson (satu per baris)."""
    out = []
    for p in paths:
        text = open(p, encoding="utf-8-sig").read().strip()
        if p.endswith(".ndjson"):
            for n, line in enumerate(text.splitlines(), 1):
                if line.strip():
                    out.append((f"{os.path.basename(p)}#{n}", json.loads(line)))
        else:
            out.append((os.path.basename(p), json.loads(text)))
    return out


def main(paths):
    total = 0
    items = load_all(paths)
    for name, b in items:
        errs = check_bundle(b)
        total += len(errs)
        if errs or len(items) <= 10:
            print(("OK  " if not errs else "ERR ") + name + ("" if not errs else f": {errs}"))
    print(f"{len(items)} bundle diperiksa, {total} pelanggaran aturan")

    # Kirim lewat pengunggah ke server tiruan yang menegakkan aturan yang sama.
    srv = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with tempfile.TemporaryDirectory() as d:
        nd = os.path.join(d, "kirim.ndjson")
        with open(nd, "w", encoding="utf-8") as f:
            for _, b in items:
                f.write(json.dumps(b) + "\n")
        env = dict(os.environ, SATUSEHAT_CLIENT_ID="x", SATUSEHAT_CLIENT_SECRET="y")
        up = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "satusehat_upload.py")
        r = subprocess.run([sys.executable, up, nd, "--base-url", f"http://127.0.0.1:{srv.server_port}"],
                           env=env, capture_output=True, text=True)
        print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[-500:])
        # Kirim ulang: semua harus dilewati (tidak ada POST baru).
        before = len(Mock.posted)
        subprocess.run([sys.executable, up, nd, "--base-url", f"http://127.0.0.1:{srv.server_port}"],
                       env=env, capture_output=True, text=True)
        resent = len(Mock.posted) - before
    srv.shutdown()
    print(f"server menerima {len(Mock.posted)} bundle, menolak {len(Mock.rejected)}, kirim ulang menambah {resent}")
    if Mock.rejected:
        print("ditolak:", Mock.rejected)
    ok = total == 0 and not Mock.rejected and len(Mock.posted) == len(items) and resent == 0
    print("HASIL:", "LULUS" if ok else "GAGAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

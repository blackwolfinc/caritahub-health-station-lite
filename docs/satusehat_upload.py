#!/usr/bin/env python3
"""Kirim ekspor Health Station Lite (FHIR R4 Bundle) ke SATUSEHAT.

Aplikasi di iMin sengaja offline. Jalankan skrip ini di komputer/server yang
terhubung internet dan sudah punya kredensial SATUSEHAT (client_id/secret).

Langkah per Bundle:
  1. Cari IHS number pasien dari NIK:
     GET /fhir-r4/v1/Patient?identifier=https://fhir.kemkes.go.id/id/nik|<NIK>
  2. Ganti semua `subject` berbasis NIK menjadi {"reference": "Patient/<IHS>"}.
  3. POST Bundle (transaction) ke /fhir-r4/v1.

Contoh:
  export SATUSEHAT_CLIENT_ID=...  SATUSEHAT_CLIENT_SECRET=...
  python3 satusehat_upload.py satusehat_20261018_1930.ndjson --env stg
  python3 satusehat_upload.py satusehat_20261018_1930.ndjson --dry-run

Hanya pustaka standar Python 3.8+. Hasil per pemeriksaan ditulis ke
<file>.hasil.json (berhasil / gagal + alasan) setelah SETIAP bundle.

Kirim ulang aman: pemeriksaan yang sudah berhasil dicatat di
satusehat_terkirim.json (di folder yang sama, atau --ledger) dan dilewati,
karena POST transaction ke SATUSEHAT selalu membuat resource baru.
"""

import argparse
import copy
import json
import os
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

NIK_SYSTEM = "https://fhir.kemkes.go.id/id/nik"
BASE_URLS = {
    "prod": "https://api-satusehat.kemkes.go.id",
    "stg": "https://api-satusehat-stg.dto.kemkes.go.id",
    "dev": "https://api-satusehat-dev.dto.kemkes.go.id",
}


def read_bundles(path):
    # utf-8-sig: file yang disimpan ulang di Windows sering diawali BOM.
    with open(path, encoding="utf-8-sig") as f:
        text = f.read().strip()
    if not text:
        return []
    if text.startswith("{") and "\n{" not in text:
        return [json.loads(text)]  # satu Bundle (ekspor dari halaman Hasil)
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def niks_in(bundle):
    found = []
    for e in bundle.get("entry", []):
        ident = (e.get("resource", {}).get("subject") or {}).get("identifier") or {}
        if ident.get("system") == NIK_SYSTEM and ident.get("value"):
            found.append(ident["value"])
    return sorted(set(found))


def with_patient(bundle, nik_to_ihs):
    """Salinan Bundle dengan subject NIK → Patient/<IHS>."""
    b = copy.deepcopy(bundle)
    for e in b.get("entry", []):
        res = e.get("resource", {})
        subj = res.get("subject")
        if not subj or "identifier" not in subj:
            continue
        nik = subj["identifier"].get("value")
        res["subject"] = {"reference": "Patient/" + nik_to_ihs[nik]}
        if subj.get("display"):
            res["subject"]["display"] = subj["display"]
    return b


class Client:
    def __init__(self, base, client_id, client_secret, timeout=30):
        self.base = base.rstrip("/")
        self.client_id = client_id
        self.client_secret = client_secret
        self.timeout = timeout
        self.token = None

    def _req(self, method, url, body=None, headers=None):
        """(status, json). Gangguan jaringan → status 0, tidak melempar."""
        data = None
        hdrs = dict(headers or {})
        if body is not None:
            data = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
            hdrs.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                raw = r.read().decode("utf-8", "replace") or "{}"
                status = r.status
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            status = e.code
        except (urllib.error.URLError, OSError, socket.timeout) as e:
            return 0, {"error": f"jaringan: {e}"}
        try:
            return status, json.loads(raw)
        except ValueError:
            return status, {"raw": raw[:500]}

    def _authed(self, method, url, body=None):
        """Panggilan ber-token; login ulang sekali bila token kedaluwarsa."""
        status, res = self._req(method, url, body, self._auth())
        if status == 401:
            self.login()
            status, res = self._req(method, url, body, self._auth())
        return status, res

    def login(self):
        url = self.base + "/oauth2/v1/accesstoken?grant_type=client_credentials"
        form = urllib.parse.urlencode(
            {"client_id": self.client_id, "client_secret": self.client_secret}
        ).encode()
        status, body = self._req(
            "POST", url, form, {"Content-Type": "application/x-www-form-urlencoded"}
        )
        if status != 200 or "access_token" not in body:
            raise SystemExit(f"Login SATUSEHAT gagal ({status}): {body}")
        self.token = body["access_token"]

    def _auth(self):
        return {"Authorization": "Bearer " + self.token}

    def patient_ihs(self, nik):
        q = urllib.parse.quote(f"{NIK_SYSTEM}|{nik}", safe="")
        status, body = self._authed("GET", f"{self.base}/fhir-r4/v1/Patient?identifier={q}")
        if status == 0:
            return None, body.get("error", "jaringan")
        if status != 200:
            return None, f"cari pasien gagal ({status})"
        entries = body.get("entry") or []
        if not entries:
            return None, "NIK tidak ditemukan di SATUSEHAT"
        return entries[0]["resource"]["id"], None

    def post_bundle(self, bundle):
        return self._authed("POST", self.base + "/fhir-r4/v1", bundle)


def bundle_key(bundle):
    for e in bundle.get("entry", []):
        res = e.get("resource", {})
        if res.get("resourceType") == "Encounter":
            ids = res.get("identifier") or [{}]
            return ids[0].get("value", "?")
    return "?"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("file", help="ekspor .ndjson (Riwayat) atau .json (Hasil)")
    ap.add_argument("--env", choices=sorted(BASE_URLS), default="stg")
    ap.add_argument("--base-url", help="ganti URL dasar (mis. server uji)")
    ap.add_argument("--dry-run", action="store_true", help="cek saja, tidak mengirim")
    ap.add_argument("--ledger", help="catatan terkirim (default: satusehat_terkirim.json)")
    args = ap.parse_args(argv)

    bundles = read_bundles(args.file)
    print(f"{len(bundles)} pemeriksaan di {args.file}")
    results = []
    if args.dry_run:
        for b in bundles:
            n = [e["resource"]["resourceType"] for e in b.get("entry", [])]
            print(f"  {bundle_key(b)}: NIK {niks_in(b)} · "
                  f"{n.count('Observation')} Observation")
        return 0

    cid = os.environ.get("SATUSEHAT_CLIENT_ID")
    secret = os.environ.get("SATUSEHAT_CLIENT_SECRET")
    if not cid or not secret:
        raise SystemExit("Isi SATUSEHAT_CLIENT_ID dan SATUSEHAT_CLIENT_SECRET")
    client = Client(args.base_url or BASE_URLS[args.env], cid, secret)
    client.login()

    ledger_path = args.ledger or os.path.join(
        os.path.dirname(os.path.abspath(args.file)), "satusehat_terkirim.json")
    try:
        with open(ledger_path, encoding="utf-8") as f:
            sent = json.load(f)
    except (OSError, ValueError):
        sent = {}
    out = args.file + ".hasil.json"

    def save():
        with open(out, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        with open(ledger_path, "w", encoding="utf-8") as f:
            json.dump(sent, f, ensure_ascii=False, indent=2)

    cache = {}
    ok = 0
    for b in bundles:
        key = bundle_key(b)
        if key in sent:
            ok += 1
            results.append({"id": key, "ok": True, "dilewati": "sudah terkirim sebelumnya"})
            print(f"  = {key}: sudah terkirim, dilewati")
            save()
            continue
        mapping, error = {}, None
        for nik in niks_in(b):
            if nik not in cache:
                cache[nik] = client.patient_ihs(nik)
            ihs, err = cache[nik]
            if err:
                error = err
                break
            mapping[nik] = ihs
        if error:
            results.append({"id": key, "ok": False, "alasan": error})
            print(f"  ✗ {key}: {error}")
            save()
            continue
        status, body = client.post_bundle(with_patient(b, mapping))
        if status in (200, 201):
            ok += 1
            locs = [
                (e.get("response") or {}).get("location")
                or (e.get("response") or {}).get("resourceID")
                for e in (body.get("entry") or [])
            ]
            results.append({"id": key, "ok": True, "resource": locs})
            sent[key] = {"resource": locs}
            print(f"  ✓ {key}")
        else:
            issues = body.get("issue") or body
            results.append({"id": key, "ok": False, "status": status, "alasan": issues})
            print(f"  ✗ {key}: {'jaringan' if status == 0 else f'HTTP {status}'}")
        save()  # setelah setiap bundle: putus di tengah tidak menghapus catatan

    if not bundles:
        save()
    print(f"{ok}/{len(bundles)} terkirim · rincian: {out}")
    return 0 if ok == len(bundles) else 1


if __name__ == "__main__":
    sys.exit(main())

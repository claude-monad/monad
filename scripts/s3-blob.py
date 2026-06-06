#!/usr/bin/env python3
"""s3-blob.py — minimal, dependency-free S3 client (AWS SigV4) for MinIO blob storage.

Used by results.sh to offload large outputs to the cluster's MinIO (jobs/minio-storage.hcl),
content-addressed by output_hash. Uses only the Python stdlib (no boto3/mc/aws needed) so it
runs on every node. Path-style addressing, region us-east-1 (MinIO ignores it but signs on it).

Config via env:
  S3_ENDPOINT    host:port of the MinIO API (e.g. 100.96.31.66:9000)   [required]
  S3_ACCESS_KEY  access key                                            [required]
  S3_SECRET_KEY  secret key                                            [required]
  S3_BUCKET      bucket name (default: results)
  S3_SCHEME      http|https (default: http)

Usage:
  s3-blob.py put <key> <file>     # ensure bucket, upload file -> object <key>
  s3-blob.py get <key>            # stream object bytes to stdout
  s3-blob.py head <key>           # exit 0 if object exists, 1 if not
"""
import sys, os, hashlib, hmac, datetime, urllib.request, urllib.error

REGION = "us-east-1"
SERVICE = "s3"


def _cfg():
    ep = os.environ.get("S3_ENDPOINT")
    ak = os.environ.get("S3_ACCESS_KEY")
    sk = os.environ.get("S3_SECRET_KEY")
    if not (ep and ak and sk):
        sys.stderr.write("s3-blob: S3_ENDPOINT/S3_ACCESS_KEY/S3_SECRET_KEY must be set\n")
        sys.exit(2)
    bucket = os.environ.get("S3_BUCKET", "results")
    scheme = os.environ.get("S3_SCHEME", "http")
    return ep, ak, sk, bucket, scheme


def _sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _signed_request(method, ep, ak, sk, scheme, path, payload=b""):
    """Build and send a SigV4-signed request. path is the canonical URI (e.g. /bucket/key)."""
    host = ep
    now = datetime.datetime.now(datetime.timezone.utc)  # explicit tz; no naive utcnow()
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(payload).hexdigest()

    canonical_headers = f"host:{host}\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{amzdate}\n"
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    # path-style: canonical URI is the path; query string empty
    canonical_request = (
        f"{method}\n{path}\n\n{canonical_headers}\n{signed_headers}\n{payload_hash}"
    )
    scope = f"{datestamp}/{REGION}/{SERVICE}/aws4_request"
    string_to_sign = (
        "AWS4-HMAC-SHA256\n"
        f"{amzdate}\n{scope}\n"
        f"{hashlib.sha256(canonical_request.encode()).hexdigest()}"
    )
    k_date = _sign(("AWS4" + sk).encode("utf-8"), datestamp)
    k_region = _sign(k_date, REGION)
    k_service = _sign(k_region, SERVICE)
    k_signing = _sign(k_service, "aws4_request")
    signature = hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={ak}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    url = f"{scheme}://{host}{path}"
    req = urllib.request.Request(url, data=payload if method in ("PUT", "POST") else None, method=method)
    req.add_header("Host", host)
    req.add_header("x-amz-content-sha256", payload_hash)
    req.add_header("x-amz-date", amzdate)
    req.add_header("Authorization", authorization)
    return req


def _do(req):
    try:
        resp = urllib.request.urlopen(req, timeout=60)
        return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        sys.stderr.write(f"s3-blob: connection error: {e}\n")
        sys.exit(3)


def ensure_bucket(ep, ak, sk, scheme, bucket):
    req = _signed_request("PUT", ep, ak, sk, scheme, f"/{bucket}")
    code, body = _do(req)
    # 200 created; 409 BucketAlreadyOwnedByYou / BucketAlreadyExists — both fine for us.
    if code in (200, 409):
        return
    sys.stderr.write(f"s3-blob: create bucket failed ({code}): {body[:300]!r}\n")
    sys.exit(4)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    op, key = sys.argv[1], sys.argv[2]
    ep, ak, sk, bucket, scheme = _cfg()
    path = f"/{bucket}/{key}"

    if op == "put":
        if len(sys.argv) < 4:
            sys.stderr.write("s3-blob: put needs <key> <file>\n"); sys.exit(2)
        with open(sys.argv[3], "rb") as f:
            payload = f.read()
        ensure_bucket(ep, ak, sk, scheme, bucket)
        code, body = _do(_signed_request("PUT", ep, ak, sk, scheme, path, payload))
        if code == 200:
            return
        sys.stderr.write(f"s3-blob: put failed ({code}): {body[:300]!r}\n"); sys.exit(5)
    elif op == "get":
        code, body = _do(_signed_request("GET", ep, ak, sk, scheme, path))
        if code == 200:
            sys.stdout.buffer.write(body); return
        sys.stderr.write(f"s3-blob: get failed ({code}): {body[:300]!r}\n"); sys.exit(6)
    elif op == "head":
        code, _ = _do(_signed_request("HEAD", ep, ak, sk, scheme, path))
        sys.exit(0 if code == 200 else 1)
    else:
        sys.stderr.write(f"s3-blob: unknown op {op}\n"); sys.exit(2)


if __name__ == "__main__":
    main()

# Update-mechanism manifest fixtures

Committed `manifest.json` samples for **manual** verification of the §10.9
update mechanism (VERIFICATION_GUIDE §22.23). The automated unit/widget tests
build their JSON inline (`test/domain/models/update_manifest_test.dart`,
`test/services/update/http_update_check_service_test.dart`); these files exist so
a verifier can serve a real endpoint without standing up the production CDN.

| File | Purpose |
|---|---|
| `manifest_update_available.json` | A newer release (`99.0.0`, non-mandatory) → the update banner appears. Carries `changelog_url`, per-platform `downloads`/`checksums`, and `server_time`. |
| `manifest_mandatory.json` | A newer release (`99.0.1`) with `"mandatory": true` → non-dismissible banner. |
| `manifest_up_to_date.json` | An old release (`0.0.1`) → the app is current; banner stays hidden and the manual check reports "You're on the latest version". |
| `manifest_malformed.json` | Deliberately invalid JSON → soft-fail (no crash, no banner; the manual check shows the non-fatal error). |

## Serving them

Point the running app's manifest endpoint at one of these files. The endpoint
URL is `kUpdateManifestUrl` in
`lib/services/update/http_update_check_service.dart`
(`https://updates.wavecrux.app/manifest.json`). For local verification, serve
this directory and temporarily route that host to it (e.g. an `/etc/hosts`
entry + a local TLS proxy, or a debug build that overrides the `manifestUri`):

```bash
# From this directory:
python3 -m http.server 8099
# then GET http://localhost:8099/manifest_update_available.json
```

The `99.0.0` / `99.0.1` versions sort above any real build version, so the
"available" and "mandatory" fixtures trigger regardless of the version the build
reports; `0.0.1` sorts below it, so the "up to date" fixture always reads as
current.

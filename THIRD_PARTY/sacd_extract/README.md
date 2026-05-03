# sacd_extract (vendored)

SACDRipper bundles a prebuilt `sacd_extract` CLI and invokes it as a child
process. The binary itself is **not** part of this repository — it is fetched
from a GitHub Release by `scripts/bootstrap.sh` and dropped into
`SACDRipper/Resources/sacd_extract` before the Xcode build.

## Provenance

- **Upstream:** https://github.com/sacd-ripper/sacd-ripper
- **Fork actually built:** https://github.com/EuFlo/sacd-ripper (EuFlo's
  enhanced fork — the upstream is unmaintained and the EuFlo fork is what
  actually works against modern PS3 / Sony BD player network servers)
- **Version:** 0.3.9.3 build 173, macOS arm64
- **Original distribution:** `sacd_extract-0.3.9.3-173-macOS-arm.zip` from
  EuFlo's release page

## Verification

The binary shipped with each SACDRipper release is the byte-for-byte file
fetched from EuFlo. Its SHA-256 is pinned in `scripts/bootstrap.sh` so a
silent swap upstream would fail verification at build time:

```
6dbfe5c68a2503d8645f75aaf7328a3b318987a35eb48a3137f65e1168be415d  sacd_extract
```

## License

`sacd_extract` is licensed under the **GNU General Public License v3.0** (see
`LICENSE.GPL` in this directory). SACDRipper invokes it as a separate process
via `Process` / `NSTask` — there is no linking, so SACDRipper's own Swift
sources remain under MIT (see `/LICENSE` at the repo root).

Per GPL §6, anyone redistributing SACDRipper builds (which include this
binary) must accompany them with either the corresponding source or a written
offer to provide it. The corresponding source is the EuFlo fork URL above —
it is freely cloneable and buildable from the tag matching the version above.

## Why vendor a prebuilt binary instead of building from source?

EuFlo's fork has no off-the-shelf macOS-arm64 build pipeline; the public
release zip is the simplest and most reproducible artifact to consume. If you
prefer to build it yourself, replace the file at
`SACDRipper/Resources/sacd_extract` with your own build (same path, +x bit
set) and update the SHA-256 in `scripts/bootstrap.sh`.

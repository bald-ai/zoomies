# AGENTS.md

- Build with `swift build` and test with `swift test`.
- Package with `./scripts/build_app.sh`; preserve the signing identity in `git config zoomies.signingIdentity` so macOS permissions survive app replacement.
- Promo video work lives in `promo/` (see `promo/HANDOFF.md`). Always finish by copying the fresh render to `~/Desktop/zoomies-promo_vN.mp4`, incrementing N (never overwrite; v1 = `zoomies-promo.mp4`, v2 = `zoomies-promo_v2.mp4`).

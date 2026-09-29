# AGENTS.md

- Build with `swift build` and test with `swift test`.
- Package with `./scripts/build_app.sh`; preserve the signing identity in `git config zoomies.signingIdentity` so macOS permissions survive app replacement.
- When I ask to build, rebuild, reinstall, run, or update the app, the goal is always an up-to-date `/Applications/Zoomies.app`: run `./scripts/build_app.sh`, quit any running Zoomies, replace `/Applications/Zoomies.app` with `dist/Zoomies.app` (`rm -rf` then `ditto`), and launch it from `/Applications`. Don't leave me running the `dist/` copy.
- Promo video work lives in `promo/` (see `promo/HANDOFF.md`). Always finish by copying the fresh render to `~/Desktop/zoomies-promo_vN.mp4`, incrementing N (never overwrite; v1 = `zoomies-promo.mp4`, v2 = `zoomies-promo_v2.mp4`).

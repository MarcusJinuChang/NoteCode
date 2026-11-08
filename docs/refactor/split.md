# The split: public `NoteCode`, private `NoteCode-AppStore`

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. This happens after 1.2.0 ships, once 2X has
emptied general code of Pro (`check-seam.sh` at 0) and `build-open-source.sh`
passes. Marcus does every GitHub and Xcode step; a session writes files and
checks.

**The one hard rule:** `https://marcusjinuchang.github.io/NoteCode/privacy`
(and `/support`) is compiled into shipped builds (`AppInfo.privacyPolicy`)
and is in App Store Connect. After **every** step below, `curl -I` both and
expect 200. GitHub Free serves no Pages from a private repo, so the pages
move before the repo does.

## S1. The pages move first

1. **Create the user-site repo `MarcusJinuChang.github.io`** (public), with
   `NoteCode/privacy.md` and `NoteCode/support.md` copied from `gh-pages`,
   keeping its front matter and `_config.yml` settings, and `app-ads.txt` at
   the root. The ads file is ROADMAP › After it's live, 5: AdMob reads it
   from the developer site's root, which the project site can't serve.
2. **Until S4, nothing changes.** The project repo's Pages win for
   `/NoteCode/` while it has them.
3. **After S4, check the handover.** When the project's Pages go off, the
   user site should serve the same URLs. Verify it, don't assume it. If
   either URL 404s, make the old repo public again at once, then work out
   why.
4. **The fallback:** GitHub Pro (free in the GitHub Student Developer Pack)
   serves Pages from a private repo.

## S2. Editions in the project (needs 0F)

Marcus does the Xcode parts in one PR; a session writes everything else and
checks it.

- **`Config/Shared.xcconfig`** holds every setting the two projects share,
  lifted from the committed release settings (0F). That includes the
  alternate-icon setting, and `PRODUCT_NAME` and `PRODUCT_MODULE_NAME`
  pinned to `NoteCode`, so `@testable import NoteCode` and `TEST_HOST` hold
  in both.
- **The public settings.** `Config/OpenSource.xcconfig` holds the bundle id
  prefix and an empty team. A gitignored `Config/Local.xcconfig` overrides
  them for anyone building it.
- **The plist and the manifest.** `Info.plist` and `PrivacyInfo.xcprivacy`
  leave `NoteCode/` for `OpenSource/` and `AppStore/`, so neither project
  sees both: `INFOPLIST_FILE`, plus a membership exception per edition
  folder.
- **The private project:**
  - **Version and build.** `Config/Version.xcconfig` (0F) moves to
    `AppStore/Version.xcconfig`, so an upload never edits a public file.
  - **The Pro code.** `git mv NoteCode/Pro Pro`, and the Pro tests with
    `NoteCode.storekit` go to `ProTests/`. `TipJarTests` loads the storekit
    file from the test bundle.
  - **`NoteCodeAppStore.xcodeproj`** is made by **copying** today's project
    file, then adjusting it. It keeps the project-level Debug and Release
    settings.
    - The app target covers `NoteCode/`, `Pro/` and `AppStore/`, and links
      Google Mobile Ads.
    - The test target covers `NoteCodeTests/` and `ProTests/`.
- **`NoteCode.xcodeproj`** becomes the public project and drops Google
  Mobile Ads.
- **`scripts/debug-launch.sh`** takes the bundle id as an argument.
- **Check against build 4.** Archive the App Store project, then compare it
  with build 4's:
  - `plutil -p` of `Info.plist`, which includes `UIApplicationSceneManifest`,
    `UTExportedTypeDeclarations` and the ad keys;
  - the privacy manifest;
  - `codesign -d --entitlements` (the project has no entitlements file).

  Only the build number may differ.

## S3. The public snapshot (two PRs)

1. **Export and scan.**
   - **The allow-list.** `scripts/public-paths.txt` lists what goes public.
     Everything else stays:
     - `Pro/`, `AppStore/`, `ProTests/` and `server/`;
     - `docs/release-1.0/`, `docs/site/` and `docs/refactor/`;
     - `shipping.md`, `run-proxy-contract.md`,
       `the-list-s-foot-and-the-tip-jar.md` and `ai-features.md`;
     - the archived P and R streams.
     - `lessons.md` may go public; Marcus decides.
   - **The export.** `scripts/export-public.sh` copies the allow-list into
     an empty directory.
   - **The scans.** Run `gitleaks detect --no-git` on it, then grep for the
     AdMob ids, the proxy URL, the team id and the product ids. Expect no
     hits.
   - **A clean build.** A fresh clone of the export builds and its tests
     pass.
2. **Public docs.**
   - A README for people who find the repo, and `LICENSE` (Apache-2.0).
   - `NOTICE`: "NoteCode" and the icon are not licensed. Third-party
     notices come from `Acknowledgements.txt`; HighlightSwift, highlight.js
     and SwiftMath are all compatible.
   - `CONTRIBUTING.md`: build, test, the scripts, how a feature plugs in.
   - `SECURITY.md`, and CI from 0E.
   - A public AGENTS.md without the private rules.
   - Public versions of the roadmap, timeline and checklist, without
     pricing, App Review or revenue.
   - Run `/security-review` on the export.

## S4. GitHub (Marcus)

1. Rename `NoteCode` to `NoteCode-AppStore`, then make it private. It keeps
   its history, issues and PRs #1–#123. Check the URLs.
2. Create a new public `NoteCode`, and push the snapshot as one root commit.
   Don't turn on Pages; the user site serves them. Check the URLs again.

## S5. The private repo, rebuilt on the public one

1. In `NoteCode-AppStore`, tag today's `main` as `pre-split` and push the
   tag.
2. Add the public repo as `upstream`. The new `main` is `upstream/main` plus
   one commit, "App Store layer", which holds:
   - `Pro/`, `AppStore/`, `ProTests/` and `server/`;
   - `docs/private/`, with the docs S3 left out plus Marcus's files from
     0B;
   - `NoteCodeAppStore.xcodeproj`;
   - a private `CLAUDE.md` with the rules that don't go public: local
     edits, the team, releases.
3. **Optional:** `git replace --graft` joins the old history to the new
   root locally, for `git blame` across the split.
4. `scripts/sync-upstream.sh` fetches `upstream` and merges `upstream/main`.
5. **Done when** a TestFlight build from the private repo passes a sandbox
   purchase and a Run.

## S6. How work flows afterwards

- **A general change** is a PR in the public repo. The private repo then
  runs `sync-upstream.sh`. That never conflicts, because the private repo
  only adds paths and never edits a public file.
- **A Pro change** is a PR in the private repo. If it needs a new hook, the
  hook goes upstream first, then the feature privately.
- **Memory.** Update the memory files (paths, repo names) with
  `/consolidate-memory`.

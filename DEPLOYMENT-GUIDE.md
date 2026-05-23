# ONLYOFFICE Mobile-Unblocked Deployment Guide

## Overview

This guide explains how to build and deploy our patched ONLYOFFICE DocumentServer
to the Synology DS925+ NAS. The patches lift mobile-editing restrictions in the
community edition so the in-browser editor and the ONLYOFFICE iOS app can edit
documents instead of being forced into view-only mode.

## How the build actually works

This is the most important section. Every other step assumes you understand
the shape of the build, because that's where past versions of this project
silently broke.

The official `onlyoffice/documentserver:9.2.1` image ships **compiled,
minified, deploy-ready** assets at `/var/www/onlyoffice/documentserver/web-apps/`:
generated sprite LESS files, packed JS bundles, mobile webpack output, etc.
Those are produced by ONLYOFFICE's grunt build from the source tree in their
[web-apps repo][web-apps].

Our `web-apps` submodule is a **fork containing source-level patches**. It is
*not* prebuilt — it contains `.jsx`, source `.js`, source `.less`, etc. You
cannot just copy the source over the base image's web-apps directory and
expect nginx to serve it. Doing so removes all the generated artifacts nginx
needs (sprite LESS files, packed bundles, mobile webpack output), which is
why a previous revision of this project resulted in "the document never
opens" with 404s for `iconsbig@1x.less` and friends.

The current Dockerfile is therefore **multi-stage**:

```
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: webapps-builder (FROM node:18-bookworm)            │
│                                                             │
│  COPY ./web-apps  →  /build/web-apps                        │
│  cd /build/web-apps/build                                   │
│  npm install                                                │
│  NODE_ENV=production grunt --force --verbose                │
│                                                             │
│  Output: /build/web-apps/deploy/web-apps/                   │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: runtime (FROM onlyoffice/documentserver:9.2.1)     │
│                                                             │
│  COPY --from=webapps-builder ... → web-apps  (OVERLAY)      │
│  chown -R ds:ds web-apps                                    │
└─────────────────────────────────────────────────────────────┘
```

**Important: Stage 2 uses an overlay copy, not a destructive replace.**
The base image's `.deb` package ships a small number of files that the
web-apps grunt build does NOT produce — most importantly
`apps/api/documents/api.js.tpl`, which the runtime entrypoint expects to
exist and `cp`s into `apps/api/documents/api.js` at container start.
If we `rm -rf` the web-apps directory before copying, the container fails
to start cleanly. `COPY` already overwrites file-by-file, which gets our
patches in while leaving the .deb-installed files intact.

### sdkjs source dependency (build-time only)

The grunt-inline plugin processes `<script src="...?__inline=true">` tags
by reading the referenced files at build time and embedding their contents
directly into the resulting `index.html`. The `index.html.deploy` templates
inside `web-apps/apps/` reference one file outside the web-apps tree:
`../../../../../../sdkjs/common/device_scale.js`. That resolves to
`/build/sdkjs/common/device_scale.js` in the builder container — a sibling
of `web-apps/`.

`build_image.sh` reads the SHA the superproject pins for the `sdkjs`
submodule (`git ls-tree HEAD sdkjs`) and passes it to `docker build` as
`--build-arg SDKJS_COMMIT=...`. The Dockerfile then `curl`s just that one
file from `raw.githubusercontent.com/ONLYOFFICE/sdkjs/<SHA>/common/device_scale.js`.
This means the inlined sdkjs file always matches the version pinned by
the superproject — no manual drift to track when bumping ONLYOFFICE versions.

If a future ONLYOFFICE version adds new `sdkjs/...?__inline=true` references,
the post-build assertion in the Dockerfile will fail the build with a
pointer to add more files to the curl step. To find any such references in
the source: `grep -rho 'sdkjs/[^"]*__inline=true' web-apps/apps`.

The grunt default task (defined in [web-apps/build/Gruntfile.js][gruntfile])
builds, for each editor (documenteditor, spreadsheeteditor, presentationeditor,
pdfeditor, visioeditor):

- `deploy-app-main` — desktop editor (RequireJS bundle + LESS + sprites)
- `deploy-app-mobile` — Framework7-React webpack build for the mobile UI
- `deploy-app-embed` — embedded read-only viewer
- `deploy-app-forms` (documenteditor only) — fillable forms

Plus the shared `common` bundle (api, sdk, socketio, jquery, etc.).

[web-apps]: https://github.com/ONLYOFFICE/web-apps
[gruntfile]: web-apps/build/Gruntfile.js

## Patches maintained in our web-apps fork

Two commits on top of upstream `c2074bbff6` (ONLYOFFICE hotfix/v9.2.1):

| Commit | Files | Change |
|--------|-------|--------|
| `332968ad2b` | `apps/common/main/lib/util/utils.js` | `isMobile = false` — disables mobile user-agent detection so the desktop editor loads even on mobile browsers |
| `332968ad2b` | `apps/{de,pe,se,ve}/mobile/src/lib/patch.jsx` | `isSupportEditFeature() => true` |
| `332968ad2b` | `apps/{de,pe,se,ve}/mobile/src/store/appOptions.js` | Extend `canLicense` to also accept `ConnectionsOS` and `UsersCountOS` license types |
| `4f36fffbf5` | `apps/{de,pe,se,ve}/mobile/src/controller/Main.jsx` | Same `canLicense` extension at the controller level (needed by iOS app path) |
| `4f36fffbf5` | `apps/documenteditor/mobile/src/controller/Main.jsx` | `forceView` default changed from `true` to `false` so mobile clients open in edit mode |

(`de` = documenteditor, `pe` = presentationeditor, `se` = spreadsheeteditor, `ve` = visioeditor.)

## Architecture

```
┌──────────────────────────────────────────┐
│ Xubuntu 24.04 Build System               │
│                                          │
│  build_image.sh                          │
│  ├─ docker build (multi-stage)           │
│  │   ├─ Stage 1: grunt build web-apps    │
│  │   └─ Stage 2: layer onto 9.2.1 image  │
│  ├─ Tag with version                     │
│  └─ Save to images/*.tar.gz              │
└──────────────────────────────────────────┘
              │ SCP transfer
              ▼
┌──────────────────────────────────────────┐
│ Synology NAS DS925+                      │
│                                          │
│  deploy_on_nas.sh                        │
│  ├─ Load Docker image                    │
│  └─ Restart compose stack                │
└──────────────────────────────────────────┘
```

## Directory Structure on NAS

```
/volume1/docker/
├── onlyoffice/
│   ├── onlyoffice7/                   # Old v7.5.1
│   ├── onlyoffice9/                   # v9.2.1 official (rollback target)
│   ├── customfonts/                   # Shared custom fonts
│   └── images/                        # Stored tar.gz images
└── compose-stacks/
    └── onlyoffice9-unblocked/         # Patched mobile-unblocked
        ├── docker-compose.yml
        └── logs/
```

Rollback path: switch Nextcloud's ONLYOFFICE Docs address back to the
`onlyoffice9` container (the unpatched official 9.2.1 stack). It stays
warm so you can flip back instantly if a patched build misbehaves.

## Step-by-Step Deployment

### 1. Build on Xubuntu

```bash
cd /mnt/fox-docker/DocumentServer-unblocked

chmod +x build_image.sh deploy_on_nas.sh

./build_image.sh
# Choose version tagging option.
# Image will be saved to: images/onlyoffice-mobile-unblocked-*.tar.gz
```

**Expected build time:** ~15-30 minutes on first build. The grunt stage
runs the full ONLYOFFICE web-apps build (~5 editors × 3-4 sub-builds each,
including a webpack build per mobile editor). Subsequent rebuilds with no
`package*.json` changes will reuse Docker layer cache for `npm install` and
be faster.

### 2. Deploy on NAS

```bash
# On NAS
cd /volume1/docker/DocumentServer-unblocked
./deploy_on_nas.sh
```

The script loads the latest `images/onlyoffice-mobile-unblocked-*.tar.gz`
and restarts the compose stack at `/volume1/docker/compose-stacks/onlyoffice9-unblocked/`.

### 3. Sanity-check the deploy

```bash
cd /volume1/docker/compose-stacks/onlyoffice9-unblocked
sudo docker compose logs --tail=200 | grep -E "(error|ERROR|404)"
```

Expected: no 404s for sprite/LESS files, no nginx errors about missing
files in `web-apps/`. The harmless noise you can ignore:

- `find: '/var/www/onlyoffice/Data/certs': No such file or directory`
- `cat: /proc/1/cpuset: No such file or directory`
- `basename: missing operand`
- `notifyLicenseExpiration(): expiration date is not defined`
- `EACCES ... .cache/pkg/.../sharp` (does not affect document loading)

If something looks broken, switch Nextcloud's ONLYOFFICE Docs address
back to the `onlyoffice9` container (unpatched official) until you can
diagnose. See Troubleshooting.

### 4. Confirm Nextcloud is pointing at the right container

ONLYOFFICE Docs address: https://onlyoffice9-unblocked.chasiubao.net/

ONLYOFFICE Docs address for internal requests from the server: http://onlyoffice9-unblocked/

## Updating to a Newer ONLYOFFICE Version

This is the reproducible path. Stick to these steps.

### A. Update the web-apps submodule (rebase patches)

```bash
cd /mnt/fox-docker/DocumentServer-unblocked/web-apps

# Note the upstream remote URL — verify it points at github.com/ONLYOFFICE/web-apps,
# not our fork. Add it if missing:
git remote -v
git remote add upstream https://github.com/ONLYOFFICE/web-apps.git  # only if not already set

git fetch upstream

# Identify the upstream tag/branch that matches the new DocumentServer version.
# For 9.3.0 this is typically the hotfix/v9.3.0 branch or v9.3.0 tag.
# Rebase our two patches on top:
git rebase upstream/hotfix/v9.3.0   # adjust target ref as appropriate

# Resolve conflicts. The patches touch well-known mobile editor files
# (see the "Patches maintained" table above); upstream is unlikely to
# refactor those files dramatically between minor versions.

git push --force-with-lease origin <our-branch>
```

### B. Update the DocumentServer-unblocked superproject

```bash
cd /mnt/fox-docker/DocumentServer-unblocked

# Point the submodule at the new web-apps commit
git -C web-apps log -1 --format='%H'   # confirm we're on the rebased tip
git add web-apps

# Bump the base image version in the Dockerfile
# Edit Dockerfile: FROM onlyoffice/documentserver:9.3.0  (Stage 2 only)
$EDITOR Dockerfile

git commit -m "Update to ONLYOFFICE 9.3.0"
git push
```

### C. Rebuild and redeploy

```bash
./build_image.sh                          # produces a new images/*.tar.gz
scp images/onlyoffice-mobile-unblocked-*.tar.gz \
    admin@nas:/volume1/docker/onlyoffice/images/
# Then on NAS:
./deploy_on_nas.sh
```

### D. Verify the patches actually took effect

**Static check (most reliable — run before exposing to clients):** the
`isMobile = false` patch causes terser to dead-code-eliminate the mobile
user-agent regex from the compiled bundle. So a stripped bundle is the
fingerprint of a successful patched build.

```bash
sudo docker compose exec onlyoffice bash -c '
  grep -c "android|avantgo" \
    /var/www/onlyoffice/documentserver/web-apps/apps/documenteditor/main/app.js'
# Expected: 0       (patched — regex eliminated)
# If 1:           the patched web-apps source was not built into the bundle.
```

And the iOS license patch should appear in the mobile bundle:

```bash
sudo docker compose exec onlyoffice bash -c '
  grep -c "ConnectionsOS" \
    /var/www/onlyoffice/documentserver/web-apps/apps/documenteditor/mobile/dist/js/app.js'
# Expected: 1 or more
```

**Functional check:**

- Desktop browser: open a document via Nextcloud; it should load and
  display the desktop editor UI (toolbars etc.), not the mobile UI.
- iOS via Nextcloud: open a document in the ONLYOFFICE iOS app; it
  should open in **edit mode**, not view-only, and should not show the
  "community version does not allow editing" message.

If either fails, see Troubleshooting below.

## Rollback

If a patched build misbehaves in production, change Nextcloud's
"ONLYOFFICE Docs address" back to the unpatched `onlyoffice9` container.
That stack stays running so the switch is instant.

## Cloudflare DNS Setup

Each container has its own Cloudflare-Tunnel subdomain on the NAS:

- `onlyoffice.yourdomain.com` → `onlyoffice9` (unpatched official, rollback)
- `onlyoffice-mobile.yourdomain.com` → `onlyoffice9-unblocked` (patched)

## Troubleshooting

### Documents never open / nginx 404s for `*.less` files

This means the runtime image is serving raw source instead of built output.
Check:

```bash
sudo docker compose exec onlyoffice ls \
  /var/www/onlyoffice/documentserver/web-apps/apps/documenteditor/main/resources/less/sprites/
```

Should contain files like `iconsbig@1x.less`. If empty or missing, the
multi-stage build failed silently or you have an old image. Rebuild from
scratch with `docker build --no-cache`.

### Browser editor still treats device as mobile

Check whether the userAgent regex made it into the compiled bundle:

```bash
sudo docker compose exec onlyoffice grep -c "android|avantgo" \
  /var/www/onlyoffice/documentserver/web-apps/apps/documenteditor/main/app.js
```

If this returns `1`, the `apps/common/main/lib/util/utils.js` patch did
not make it into the built bundle. Rebuild and verify the web-apps submodule
is on the patched fork's tip, not upstream.

### iOS app says "community version does not allow editing"

The license-check patches (controller and store `canLicense` extensions) didn't
make it into the built mobile bundle. Most common cause: web-apps submodule
pointing at an unpatched commit. Verify with:

```bash
cd web-apps
git log --oneline | head -5    # should show our two patch commits at the top
```

### Mobile editor opens view-only via iOS app

The `forceView` default patch in `documenteditor/mobile/src/controller/Main.jsx`
was not applied. Same diagnosis path as above.

### grunt build fails during Stage 1

```bash
# Build with full output to see which task failed
docker build --no-cache --progress=plain -t onlyoffice-mobile-unblocked:debug .
```

Common causes:
- `npm install` fails on native module (cairo/sharp): missing system dep —
  add to the apt-get list in Stage 1.
- A patch landed on a file upstream renamed/moved in this version: rebase
  the web-apps fork onto the new upstream tag.

### View logs

```bash
# All container logs
sudo docker compose -f /volume1/docker/compose-stacks/onlyoffice9-unblocked/docker-compose.yml logs -f

# Just nginx (where the 404 errors land)
sudo docker compose exec onlyoffice tail -f /var/log/onlyoffice/documentserver/nginx.error.log

# Just docservice
sudo docker compose exec onlyoffice tail -f /var/log/onlyoffice/documentserver/docservice/out.log
```

## Notes

- **JWT Secret**: Uses the same secret as the official ONLYOFFICE instance for compatibility
- **Network**: Uses `nextcloud_internal` network for Nextcloud integration
- **Custom Fonts**: Shared with official instances via `/customfonts` mount
- **Image Size**: ~2-3 GB per tar.gz
- **Build Time**: ~15-30 minutes (grunt build dominates)

## Quick Reference Commands

```bash
# Build (Xubuntu)
./build_image.sh

# Transfer (Xubuntu → NAS)
scp images/*.tar.gz admin@nas:/volume1/docker/onlyoffice/images/

# Deploy (NAS)
./deploy_on_nas.sh

# Status / logs (NAS)
cd /volume1/docker/compose-stacks/onlyoffice9-unblocked
sudo docker compose ps
sudo docker compose logs -f
```

## Security Considerations

- Keep JWT_SECRET secure and consistent across instances
- Use HTTPS via Cloudflare Tunnel
- Regularly update to latest ONLYOFFICE versions with security patches
- After each rebuild, run the verification checks in section "D. Verify
  the patches actually took effect" before relying on the deploy

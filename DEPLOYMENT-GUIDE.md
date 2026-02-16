# ONLYOFFICE Mobile-Unblocked Deployment Guide

## Overview

This guide explains how to build and deploy your mobile-unblocked version of ONLYOFFICE DocumentServer to your Synology DS925+ NAS.

## Architecture

```
┌──────────────────────────────────────────┐
│ Xubuntu 24.04 Build System               │
│                                          │
│  build_image.sh                          │
│  ├─ Build Docker image                   │
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
│  ├─ Deploy to test or prod              │
│  └─ Restart container                    │
└──────────────────────────────────────────┘
```

## Directory Structure on NAS

```
/volume1/docker/onlyoffice/
├── onlyoffice7/                    # Old v7.5.1
├── onlyoffice9/                    # Current v9.2.1 official
├── onlyoffice9-unblocked-test/        # NEW - Testing mobile-unblocked
│   ├── docker-compose.yml
│   └── logs/
├── onlyoffice9-unblocked/             # NEW - Production mobile-unblocked
│   ├── docker-compose.yml
│   └── logs/
├── customfonts/                    # Shared custom fonts
└── images/                         # NEW - Stored tar.gz images
```

## Step-by-Step Deployment

### 1. Build on Xubuntu (One-Time Setup)

```bash
# On your Xubuntu build system
cd /path/to/DocumentServer-unblocked

# Make scripts executable
chmod +x build_image.sh deploy_on_nas.sh

# Build the image
./build_image.sh
# Choose version tagging option
# Image will be saved to: images/onlyoffice-mobile-unblocked-*.tar.gz
```

### 2. Transfer to NAS

```bash
# Create images directory on NAS (one-time)
ssh admin@your-nas-ip
mkdir -p /volume1/docker/onlyoffice/images
exit

# Transfer the image
scp images/onlyoffice-mobile-unblocked-*.tar.gz admin@your-nas-ip:/volume1/docker/onlyoffice/images/
```

### 3. Set Up Test Environment on NAS (First Time)

```bash
# SSH to NAS
ssh admin@your-nas-ip

# Create test environment directory
sudo mkdir -p /volume1/docker/onlyoffice/onlyoffice9-unblocked-test/logs

# Copy docker-compose.yml
# (You'll need to transfer docker-compose-nas.yml from your Windows machine)
sudo nano /volume1/docker/onlyoffice/onlyoffice9-unblocked-test/docker-compose.yml
# Paste the contents and modify if needed
```

### 4. Deploy on NAS

```bash
# On NAS, in the DocumentServer-unblocked directory (after transferring deploy script)
cd /volume1/docker/onlyoffice/images/../..  # Adjust path
./deploy_on_nas.sh

# Choose:
# 1) Test environment (recommended first time)
# Script will load image and restart container
```

### 5. Test Mobile Editing

1. **Access via Cloudflare subdomain** (e.g., `onlyoffice-test.yourdomain.com`)
2. **Point Nextcloud to test instance:**
   - Nextcloud Settings → ONLYOFFICE → Document Server address
   - Update to test URL
3. **Test on mobile device:**
   - Open a document in Nextcloud on your phone/tablet
   - Verify you can edit (not just view)

### 6. Deploy to Production

Once tested:

```bash
# On NAS
./deploy_on_nas.sh
# Choose: 2) Production environment

# Or manually:
cd /volume1/docker/onlyoffice/onlyoffice9-unblocked
sudo docker compose down
sudo docker compose up -d
```

### 7. Update Nextcloud

Update Nextcloud to point to your production mobile-unblocked instance.

## Updating to Newer Versions

When ONLYOFFICE releases a new version:

### Update Your Fork

```bash
# On Windows
cd d:/Source/DocumentServer-unblocked

# Update web-apps submodule
cd web-apps
git fetch upstream
git merge upstream/master
# Check if mobile patch is still intact at line 370 in utils.js
# Reapply if needed

# Update DocumentServer
cd ..
git fetch upstream
git merge upstream/master
git submodule update --remote web-apps

# Update Dockerfile base version
nano Dockerfile
# Change: FROM onlyoffice/documentserver:9.3.0  (or new version)

# Commit changes
git add .
git commit -m "Update to ONLYOFFICE 9.3.0"
git push
```

### Rebuild and Deploy

```bash
# On Xubuntu
cd DocumentServer-unblocked
./build_image.sh  # New version with new tag
# Transfer to NAS
# Deploy to test first, then production
```

## Blue/Green Deployment

You already have this pattern with onlyoffice7 and onlyoffice9. Continue it:

1. **Test** = onlyoffice9-unblocked-test (Cloudflare subdomain A)
2. **Production** = onlyoffice9-unblocked (Cloudflare subdomain B)
3. **Rollback** = onlyoffice9 (original official version)

Switch between them by:
- Updating Nextcloud ONLYOFFICE settings
- Or using Cloudflare DNS routing

## Cloudflare DNS Setup

Example subdomains:
- `onlyoffice.yourdomain.com` → onlyoffice9 (current official)
- `onlyoffice-mobile.yourdomain.com` → onlyoffice9-unblocked (production mobile-unblocked)
- `onlyoffice-test.yourdomain.com` → onlyoffice9-unblocked-test (testing)

All route through Cloudflare Tunnel to your NAS.

## Troubleshooting

### Check if mobile patch is active

```bash
# In browser console on mobile device:
Common.Utils.isMobile
# Should return: false
```

### View logs

```bash
# On NAS
sudo docker compose -f /volume1/docker/onlyoffice/onlyoffice9-unblocked/docker-compose.yml logs -f

# Or directly:
sudo tail -f /volume1/docker/onlyoffice/onlyoffice9-unblocked/logs/documentserver.log
```

### Rebuild if needed

```bash
# On Xubuntu
./build_image.sh  # Rebuild
# Transfer to NAS
./deploy_on_nas.sh  # Redeploy
```

## Notes

- **JWT Secret**: Uses the same secret as your official ONLYOFFICE instance for compatibility
- **Network**: Uses `nextcloud_internal` network for Nextcloud integration
- **Custom Fonts**: Shared with official instances via `/customfonts` mount
- **Image Size**: ~2-3GB per tar.gz file
- **Build Time**: ~5-10 minutes on Xubuntu (depending on system)

## Quick Reference Commands

```bash
# Build (Xubuntu)
./build_image.sh

# Transfer (Xubuntu → NAS)
scp images/*.tar.gz admin@nas:/volume1/docker/onlyoffice/images/

# Deploy to test (NAS)
./deploy_on_nas.sh  # Choose option 1

# Deploy to prod (NAS)
./deploy_on_nas.sh  # Choose option 2

# Check status (NAS)
cd /volume1/docker/onlyoffice/onlyoffice9-unblocked
sudo docker compose ps

# View logs (NAS)
sudo docker compose logs -f
```

## Security Considerations

- Keep JWT_SECRET secure and consistent across instances
- Use HTTPS via Cloudflare Tunnel
- Regularly update to latest ONLYOFFICE versions with security patches
- Test thoroughly in test environment before production deployment

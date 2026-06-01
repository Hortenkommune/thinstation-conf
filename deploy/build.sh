#!/bin/bash
# Source of truth: deploy/build.sh in public/thinstation-conf.
# Rendered onto /data/build.sh by deploy/ansible/playbook.yml on every CI run.
# Edits on the host will be overwritten on the next deploy — change it here.
set -e

BUILDROOT=/data/ts72
CONFDIR=/data/conf
OUTDIR=/data/thinstation-ng/build

# --- Inject build timestamp into background ---
BUILD_TIME=$(date '+%Y-%m-%d %H:%M')
SRC_BG="$CONFDIR/ts/build/backgrounds/hortenkommune.jpg"
OUT_BG="$CONFDIR/ts/build/backgrounds/wallpaper.jpg"

if [ -f "$SRC_BG" ]; then
magick "$SRC_BG" \
    -gravity southeast \
    -font DejaVu-Sans \
    -pointsize 26 \
    -fill "rgba(255,255,255,0.65)" \
    -annotate +30+25 "Build: $BUILD_TIME" \
    "$OUT_BG"
fi

cd "$BUILDROOT"

# --- Sync entire overlay into the build tree ---
# Everything under /data/conf/ts/ maps directly to $BUILDROOT/ts/
# This covers: build configs, machine configs, package overlays, etc.
rsync -rlpt "$CONFDIR/ts/" ts/

# --- Inject secrets (not stored in git) ---
if [ -f /data/secrets/build.secrets ]; then
    source /data/secrets/build.secrets
    sed -i "s/^param tsuserpasswd.*/param tsuserpasswd   $TSUSER_PW/" ts/build/conf/*/build.conf.example
    sed -i "s/^param rootpasswd.*/param rootpasswd     $ROOT_PW/" ts/build/conf/*/build.conf.example
fi

# --- Apply package patches ---

# Add ICA_LOG_LEVEL config option to 50ica (configurable via thinstation.conf)
if ! grep -q 'ICA_LOG_LEVEL' ts/build/packages/ica/build/conf/50ica; then
cat >> ts/build/packages/ica/build/conf/50ica <<'EOF'

# --- Citrix Workspace App logging
#ICA_LOG_LEVEL              Citrix Workspace App log level (applied to module "all").
#                           One of: none, error, warning, normal, verbose, inherit
#                           "none" disables logging. Default in the shipped image is verbose.
#ICA_LOG_LEVEL=error
EOF
fi

# Inject setlog call into ica-init so each thin client applies ICA_LOG_LEVEL at boot
if ! grep -q 'ICA_LOG_LEVEL' ts/build/packages/ica/build/extra/etc/init.d/ica-init; then sed -i '/^exit 0$/i\
# Apply Citrix Workspace App log level if configured (module "all" propagates to children)\
if [ -n "$ICA_LOG_LEVEL" ] && [ -x /opt/Citrix/ICAClient/util/setlog ]; then /opt/Citrix/ICAClient/util/setlog level all "$ICA_LOG_LEVEL" >/dev/null 2>&1 || logger --stderr --tag ica-init "setlog level all $ICA_LOG_LEVEL failed"; fi\
' ts/build/packages/ica/build/extra/etc/init.d/ica-init
fi

# Force Gnome-core package to re-run merge_trunk on next build
# Apply fix to hide the gnome-keyring to pop up when logging in to the reciver.
rm -f ts/build/packages/gnome-core/build/installed

# Block ica_appprotection (we don't use this and this spams the log with errors if installed)
sed -i 's/^ica_appprotection$/!ica_appprotection/' ts/build/packages/ica/dependencies

# Force ICA package to re-run merge_trunk on next build
# (ensures overlay files from build/extra/ are applied)
rm -f ts/build/packages/ica/build/installed

# Force ICA package to re-run merge_trunk on next build
# (ensures overlay files from build/extra/ are applied)
rm -f ts/build/packages/plymouth/build/installed


# --- Backup boot-images before build (thinstation overwrites them) ---
cp -r ./build/boot-images/ ./build/boot-images-backup/

# --- Build ---
./setup-chroot -b -o --autodl

# --- Post-build ---

# Copy images to output directory
cp -r ./build/boot-images/ "$OUTDIR/"

# Rebuild iPXE bootfiles (thinstation overwrites them)
cd /data/ipxe/src/
make bin-x86_64-efi/ipxe.efi EMBED=/data/ipxe/src/boot.ipxe
make bin/undionly.kpxe EMBED=/data/ipxe/src/boot.ipxe
cp bin-x86_64-efi/ipxe.efi "$OUTDIR/boot-images/grub/efi-source/EFI/BOOT/BOOTX64.EFI"
cp bin/undionly.kpxe "$OUTDIR/boot-images/grub/efi-source/undionly.kpxe"

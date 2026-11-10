#!/usr/bin/env bash
# Install the Galaxy Book 12 ALC298 audio driver (DKMS package alc298-galaxybook)
# for every installed kernel, plus the post-network rebuild service.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CODEC_VENDOR_EXPECTED="0x10ec0298"
CODEC_SUBSYSTEM_EXPECTED="0x144dc14f"

echo "==> Checking for ALC298 codec with Samsung subsystem ${CODEC_SUBSYSTEM_EXPECTED}..."
codec_found=false
for node in /sys/class/sound/hwC*D*; do
    [ -r "$node/vendor_id" ] || continue
    if [ "$(cat "$node/vendor_id")" = "$CODEC_VENDOR_EXPECTED" ] && \
       [ "$(cat "$node/subsystem_id" 2>/dev/null)" = "$CODEC_SUBSYSTEM_EXPECTED" ]; then
        codec_found=true; break
    fi
done
$codec_found || { echo "ERROR: ALC298 with subsystem ${CODEC_SUBSYSTEM_EXPECTED} not found." >&2; exit 1; }
echo "    Found."

echo "==> Checking for conflicting model= overrides in /etc/modprobe.d..."
# (captured first: "| grep -q" under pipefail can fail at random via SIGPIPE)
overrides="$(grep -rn "model=" /etc/modprobe.d/ 2>/dev/null | grep -i "snd-hda-intel\|snd_hda_intel" || true)"
if [ -n "$overrides" ]; then
    echo "ERROR: an explicit 'model=' override for snd-hda-intel takes priority over the"
    echo "PCI-subsystem-ID quirk this patch relies on. Remove/comment it out first:"
    echo "$overrides"
    exit 1
fi

if [ -e /etc/systemd/system-sleep/galaxybook-audio ] || [ -e /usr/local/bin/galaxybook-audio-init ]; then
    echo "WARNING: the old Galaxy Book 10.6 userspace audio workaround is installed."
    echo "         Its resume hook writes the 10.6 amplifier setup over I2C and forces"
    echo "         speaker routing, fighting this driver. Remove it (galaxybook-10.6-audio's"
    echo "         uninstall.sh) before or after installing this."
fi

"$HERE/common/install-dkms.sh" alc298-galaxybook "$HERE/dkms"
echo "Reboot once (or reload snd_hda_codec_alc269) to use it. Verify:"
echo "  sudo dmesg | grep -i 'alc298\\|picked fixup'"

#!/usr/bin/env bash
# Remove the Galaxy Book 12 ALC298 audio driver; the stock snd_hda_codec_alc269
# (without the Galaxy Book quirk) is used again after a reboot.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/common/uninstall-dkms.sh" alc298-galaxybook

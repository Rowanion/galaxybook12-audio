#!/bin/bash
# Build snd-hda-codec-alc269 with the Galaxy Book 12/10.6 ALC298 patch for one
# kernel, from that kernel's own vanilla source (not a frozen copy).
set -euo pipefail
KVER="${1:?kernelver required}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HEADERS="/lib/modules/$KVER/build"
# shellcheck source=/dev/null
. "${GB_HELPER:-/usr/local/lib/galaxybook-dkms/kernel-src.sh}"

[ -d "$HEADERS" ] || { echo "ERROR: no kernel headers at $HEADERS (install kernel-devel-$KVER)" >&2; exit 1; }
SRC="$(gb_kernel_src "$KVER" sound/hda/codecs sound/hda/common)"

OUT="$HERE/out"; rm -rf "$OUT"; mkdir -p "$OUT/sound/hda"
cp -a "$SRC/sound/hda/codecs" "$SRC/sound/hda/common" "$OUT/sound/hda/"
gb_apply_patches "$HERE" "$OUT"

# --- struct layout guard -------------------------------------------------
# The patch adds a 1-bit flag to struct alc_spec in realtek.h. Only our
# alc269 module sees it; the stock snd-hda-codec-realtek-lib is compiled
# without it and allocates/uses the struct with the stock layout. That is
# only safe while the new bit fits into spare bits of an existing bitfield
# word. Refuse to build otherwise (a silent mismatch would corrupt memory).
R="$OUT/sound/hda/codecs/realtek"
layout() {  # print "<bits>" for each run of consecutive bitfield members in struct alc_spec
  awk '/^struct alc_spec \{/{s=1;next} s&&/^\};/{if(run)print run; exit}
       s{ if (match($0,/^[ \t]*unsigned int [A-Za-z0-9_]+:[ \t]*([0-9]+);/,m)) run+=m[1];
          else if ($0 ~ /^[ \t]*($|\/\*|\*)/) {} else { if(run)print run; run=0 } }' "$1"
}
added_other="$(diff "$SRC/sound/hda/codecs/realtek/realtek.h" "$R/realtek.h" | grep '^[<>]' \
  | grep -vE '^>[[:space:]]*unsigned int [A-Za-z0-9_]+:[[:space:]]*1;' || true)"
if [ -n "$added_other" ]; then
  echo "ERROR: patch changes realtek.h beyond adding 1-bit flags:" >&2; echo "$added_other" >&2; exit 1
fi
mapfile -t V < <(layout "$SRC/sound/hda/codecs/realtek/realtek.h")
mapfile -t P < <(layout "$R/realtek.h")
if [ ${#V[@]} -ne ${#P[@]} ]; then echo "ERROR: alc_spec bitfield runs changed (${#V[@]} -> ${#P[@]})" >&2; exit 1; fi
for i in "${!V[@]}"; do
  if [ $(( (V[i] + 31) / 32 )) -ne $(( (P[i] + 31) / 32 )) ]; then
    echo "ERROR: alc_spec bitfield run $i grows from ${V[i]} to ${P[i]} bits and no longer" >&2
    echo "       fits its storage word; the struct layout would differ from the stock" >&2
    echo "       snd-hda-codec-realtek-lib. The patch must be reworked for this kernel." >&2
    exit 1
  fi
done
echo "alc_spec layout guard: OK (bitfield runs ${V[*]} -> ${P[*]} bits)"

# Build only the alc269 codec module (the rest of realtek/ stays stock).
printf '%s\n' 'ccflags-y += -I$(src)/../../common' \
  'obj-m += snd-hda-codec-alc269.o' 'snd-hda-codec-alc269-y := alc269.o' > "$R/Makefile"
make -C "$HEADERS" M="$R" modules -j"${JOBS:-$(nproc)}" CONFIG_DEBUG_INFO_BTF_MODULES=
echo "Built snd-hda-codec-alc269 for $KVER"

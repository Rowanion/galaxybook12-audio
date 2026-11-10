# galaxybook12-audio

DKMS-packaged kernel patch that adds a proper Realtek HDA quirk for the ALC298
codec found in the Samsung Galaxy Book 12 (PCI subsystem ID `144d:c14f`).
Replaces the need for a userspace `hda-verb`-based amp-init hack (e.g. the
DarrenBenson speaker fix) with a native kernel driver: amplifier init, correct
speaker/headphone DAC routing, automatic speaker/headphone switching on jack
insertion, and proper suspend/resume handling.

Confirmed working on:

- Samsung Galaxy Book 12 (SM-W720) — this repo's development unit, Fedora 44,
  kernels 7.2.15 and 7.3.3.
- Samsung Galaxy Book 12 (SM-W720/SM-W727) — original target, per
  [fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux).

> **Model note:** earlier versions of this README listed the development unit
> as a Galaxy Book 10.6 (SM-W620). It is an SM-W720: 11.9″ 2160×1440 panel,
> i5-7200U, board `SM-W720`, and its speakers only work with the Book 12
> amplifier addresses (`0x31`/`0x34`; the 10.6 uses `0x34`/`0x35` and codec
> subsystem `144d:c150`, which this quirk does not match). Not tested on a 10.6.

The quirk matches purely on PCI subsystem ID (no DMI check at all), so it
applies on any hardware reporting that exact codec/subsystem combination.

## Known limitation

On the development unit, the right speaker was effectively non-functional
(very faint/no output) under this driver. The same right-channel issue was
also present under the older DarrenBenson userspace fix, so this is very
likely a hardware/amp fault on the specific unit rather than something this
patch can fix. If your right speaker works fine, this note doesn't apply to
you — please report back either way.

Do not attempt to fix this by swapping the `0x31`/`0x34` amp-selector values
in the patch — this was tried and caused a channel-crossing regression without
restoring right-channel output.

## Headphone jack

Speakers and headphones share codec pin `0x17`, which the firmware declares as
a fixed internal speaker. Measured on the SM-W720 (`tools/jack-probe`):

- **`0x17`'s own pin sense** toggles on every plug/unplug — the driver uses it
  (read raw, because the generic code treats `0x17` as an always-present
  "phantom" jack) and enables unsolicited events on it, so output switches
  immediately, also during playback.
- **`0x18`** (headset mic pin) only reports plugs that have a microphone
  contact. The generic auto-mic switch follows it, so a real 4-pole headset
  switches the input to the headset mic, while headphones without a mic (or a
  Bluetooth headphone's audio cable) keep the built-in microphone.

`experimental/force-headset-mic-on-plug.patch` instead switches the input to
the headset mic on *any* plug; not used by default because it disables the
built-in mic for plugs without a mic contact.

## What it does

`install.sh`:

1. Checks that an ALC298 codec with subsystem ID `144d:c14f` is present.
2. Checks for a conflicting `model=` override in `/etc/modprobe.d/` (a common
   leftover from older userspace audio workarounds), which would silently
   override the PCI-subsystem-ID quirk table.
3. Warns if the old Galaxy Book 10.6 userspace workaround is still installed
   (its resume hook writes the wrong amplifier setup on every wake).
4. Installs build dependencies (`dkms`, `kernel-devel`, …) if missing.
5. Registers DKMS package `alc298-galaxybook/2.0` and builds it for **every**
   installed kernel: `dkms/dkms-make.sh` takes that kernel's own vanilla
   kernel.org `sound/hda/codecs` + `sound/hda/common`, applies
   `dkms/patches/0001-sound-hda-realtek-galaxy-book12.patch` with zero fuzz,
   and builds only `snd-hda-codec-alc269` (the rest of the Realtek driver
   stays stock).
6. Only if all builds succeed, replaces any older version and installs.
7. Installs `galaxybook-dkms-catchup` (shared with the camera/accel repos):
   rebuilds after kernel updates once the network is up and notifies on
   failure.

No kernel source is vendored: each kernel gets its own matching source
(downloaded once per version, cached in `/var/cache/galaxybook-kernel-src`).

**Struct layout guard:** the patch adds a 1-bit flag to `struct alc_spec`,
which the stock `snd-hda-codec-realtek-lib` is compiled without. That is only
safe while the bit fits into spare bits of an existing bitfield word, so the
build checks this and refuses to build (instead of corrupting memory at run
time) if a future kernel changes the struct so it no longer fits.

## Usage

```bash
git clone <this-repo> galaxybook12-audio
cd galaxybook12-audio
./install.sh
sudo reboot
```

To remove: `./uninstall.sh` (stock driver again after a reboot).

## Tools

Diagnostics used to work out the jack/mic behaviour (run with `sudo`; all
save and restore every codec setting they touch):

- `tools/jack-probe` — watches pin sense of `0x17`/`0x18` while you plug/unplug.
- `tools/mic-locate` — quiet-vs-speaking recording on every input pin, normal
  and in ALC298 combo-jack headset mode, to find a headset microphone.
- `tools/mic-probe`, `tools/headset-mode-test` — earlier, narrower versions.

## Credit

The patch is based on `kernel/patches/0001-sound-hda-realtek-galaxy-book12.patch`
from [fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux),
with these changes:

- jack detection on `0x17` (raw pin sense + unsolicited events) instead of
  only the mic pin `0x18`;
- the enum hunk trimmed to one line of leading context so it applies to
  kernel 7.3 (which added `ALC236_FIXUP_HP_15_FD0XXX` right above it); on
  7.2 the result is byte-identical to the original.

The underlying register-level amp research is originally from Aurélien Croc
(AP²C)'s Windows/QEMU trace work, per both the upstream project and the
earlier DarrenBenson userspace fix.

## License

GPL-2.0-only, matching the Linux kernel.

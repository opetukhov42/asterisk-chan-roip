# chan_roip — Docker build environment (Windows + Docker Desktop)

Builds the `chan_roip` module two ways, all inside Linux containers (so Windows
line-endings, musl, and cross-toolchains are not your problem):

- **OpenWrt** — `asterisk-chan-roip` `.ipk` packages per architecture, using the official
  OpenWrt 24.10.1 SDK.
- **Vanilla Asterisk** — a plain `chan_roip.so` for a standard glibc Asterisk install.

## What you need

- Docker Desktop for Windows (WSL2 backend recommended).
- Working internet (the build downloads the OpenWrt SDK and Asterisk source).
- Disk + patience: each target downloads an SDK and compiles Asterisk 20.8.1 from source,
  so the first build for a target can take a good while and a few GB of scratch space.

## Layout

```
chan_roip_build/
├─ Dockerfile            # OpenWrt SDK build image
├─ Dockerfile.vanilla    # vanilla-Asterisk build image
├─ docker-compose.yml
├─ build.sh              # OpenWrt entrypoint: download SDK, integrate, build, collect
├─ build_vanilla.sh      # vanilla entrypoint: build chan_roip.so vs Asterisk source
├─ integrate.py          # wires the module into the feed's asterisk package (OpenWrt)
├─ src/
│  ├─ chan_roip.c             # the module
│  └─ roip.conf.sample        # sample config
└─ out/                  # results: out/<target>/*.ipk  and  out/vanilla/chan_roip.so
```

## Build

Open **PowerShell** (or Windows Terminal) in the `chan_roip_build` folder.

```powershell
docker compose build                 # build the builder image once
docker compose run --rm x86_64       # build for x86_64
docker compose run --rm x86_generic  # 32-bit x86 ("i386")
docker compose run --rm pi4          # Raspberry Pi 4
```

Results appear in `out\<target>\asterisk-chan-roip_20.8.1-*_<arch>.ipk`, e.g.
`out\x86-64\asterisk-chan-roip_20.8.1-r1_x86_64.ipk`.

Available services (see `docker-compose.yml`): `x86_64`, `x86_generic`, `pi1` (Pi1/Zero),
`pi2`, `pi3` (Pi3/Zero2), `pi4`. To build a target that isn't listed, just pass TARGET:

```powershell
docker compose run --rm -e TARGET=ipq40xx/generic x86_64
```

(The service name is irrelevant when you override `TARGET`; it only reuses the same image.)

## Vanilla (non-OpenWrt) Asterisk build

To build a plain `chan_roip.so` for a **standard glibc Asterisk install** (e.g. Debian/Ubuntu,
a from-source Asterisk, or CI), use the `vanilla` service. It fetches the Asterisk source,
configures it, and compiles just the module:

```powershell
docker compose run --rm vanilla                       # builds against Asterisk 20.8.1
docker compose run --rm -e ASTVER=20.9.0 vanilla      # or another version
```

The result is `out\vanilla\chan_roip.so` (plus `roip.conf.sample`). Install it by copying
`chan_roip.so` into your Asterisk modules dir (typically `/usr/lib/asterisk/modules/`),
putting `roip.conf` in `/etc/asterisk/`, and loading it (`module load chan_roip.so`, or
autoload).

By default it compiles the single module standalone (fast). Set `FULL_BUILD=1` to build it
through Asterisk's own build system instead:

```powershell
docker compose run --rm -e FULL_BUILD=1 vanilla
```

**Same buildopt-sum rule applies:** the module must match the running Asterisk's compile
options. This is guaranteed when your Asterisk was built from the **same version's source**
as `ASTVER`. If you run a distro package and hit a "not compiled with the same compile-time
options" error, build against that package's exact source/options (or rebuild Asterisk from
the `ASTVER` source and run that).

## Install on the OpenWrt box

Copy the `.ipk` to the device and:

```sh
opkg install ./asterisk-chan-roip_20.8.1-*_<arch>.ipk
# then enable + configure:
#   /etc/asterisk/modules.conf   -> ensure chan_roip.so loads (autoload=yes, or explicit load)
#   /etc/asterisk/roip.conf -> your device settings (a sample was installed)
/etc/init.d/asterisk restart
```

Check it loaded: `asterisk -rx "module show like roip"` and
`asterisk -rx "core show help roip"` (the CLI prefix is `roip`).

## The one caveat that actually matters: buildopt-sum matching

Asterisk refuses to load a module whose compile-time-options MD5 differs from the running
Asterisk. This build produces a module against the **current** 24.10 telephony feed. As long
as that feed still ships Asterisk **20.8.1** with the same options as your installed
firmware (the normal case for 24.10.1), the module loads fine.

If `opkg`/Asterisk complains that the module *"was not compiled with the same compile-time
options"* or the version differs, the guaranteed fix is to build and install the **base
asterisk package from the same run**, so the sums match by construction:

```powershell
docker compose run --rm -e ALSO_BUILD_BASE=1 x86_64
```

Then install both `asterisk_*.ipk` and `asterisk-chan-roip_*.ipk` from `out\x86-64\`
(`opkg install --force-reinstall ./asterisk_*.ipk ./asterisk-chan-roip_*.ipk`). This
replaces the base package with an identical-options rebuild plus your module.

## Notes / troubleshooting

- **"Could not find an SDK for <target>"** — the target/subtarget string is wrong or not in
  24.10.1. Check `opkg print-architecture` / `ubus call system board` on the device and the
  target list at `downloads.openwrt.org/releases/24.10.1/targets/`.
- **Line endings** — `integrate.py` normalises the copied `.c`/`.conf` to LF, so editing them
  on Windows is safe. If you keep this in git, a `.gitattributes` with
  `*.c text eol=lf` and `*.sh text eol=lf` avoids surprises.
- **Rebuild from scratch** — `docker compose run` starts a fresh container each time, so each
  run re-downloads the SDK. That's intentional (clean, reproducible). If you rebuild a target
  often and want to cache, add a named volume for `/home/builder` in `docker-compose.yml`.
- **Runs as non-root** inside the container (OpenWrt refuses to build as root); nothing to do
  on your side.
- **Adding the MX64 / bcm53xx later** — it's `TARGET=bcm53xx/generic`, but confirm ALSA and a
  matching installed Asterisk exist on that box first (it has no onboard audio). Run e.g.
  `docker compose run --rm -e TARGET=bcm53xx/generic x86_64`.

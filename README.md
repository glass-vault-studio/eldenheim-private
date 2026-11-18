# eldenheim-private

**Private. Never share, fork, make public or add collaborators.** The installer in this repo's releases contains
Elden Ring data converted from the owner's own copy of Elden Ring. It is for the owner's own PCs only. The mod's
source code is in the separate `eldenheim` repo; everyone else uses the public installer, which has no Elden Ring
data.

## Install on another PC

Open PowerShell (git must be signed in to this GitHub account) and paste this one line:

```powershell
$d="$env:TEMP\eldenheim-private"; if (Test-Path $d) { git -C $d pull -q } else { git clone -q --depth 1 https://github.com/glass-vault-studio/eldenheim-private $d }; powershell -ExecutionPolicy Bypass -File "$d\install.ps1"
```

It downloads the latest personal installer (about 3.4 GB) into `Downloads\Eldenheim`, checks it and starts it. In
the installer, check that the Valheim folder is right, tick the box and click Install. The Elden Ring data is built
in, so Elden Ring does not have to be installed on that PC. Keep the exe: run it again later for repair or uninstall
(Advanced).

## What is here

- `install.ps1`: the download script above.
- Releases: `EldenheimInstaller-Personal.exe` in parts (GitHub allows at most 2 GB per file) plus `SHA256SUMS.txt`.
  Only the latest release is kept.

Updated from the main repo with `tools\PublishPersonal.ps1` (after `tools\BuildInstaller.ps1 -Personal`).

<#
.SYNOPSIS
  Downloads the personal Eldenheim installer from this private repo's latest release and starts it.

.DESCRIPTION
  The installer (about 3.4 GB, with the owner's converted Elden Ring data built in) is stored as release assets in
  parts below GitHub's 2 GB limit. This script signs in with the git credentials already on this PC (Git Credential
  Manager), downloads the parts straight into one exe, checks its SHA-256 against the release's SHA256SUMS.txt and
  runs it. The installer then only asks you to check the Valheim folder and click Install.

  One line, from any PowerShell window (git signed in to the right GitHub account):
    $d="$env:TEMP\eldenheim-private"; if (Test-Path $d) { git -C $d pull -q } else { git clone -q --depth 1 https://github.com/glass-vault-studio/eldenheim-private $d }; powershell -ExecutionPolicy Bypass -File "$d\install.ps1"

  NEVER share this repo, the release or the exe: they contain Elden Ring data.

.PARAMETER NoStart
  Download and check only; do not start the installer.

.PARAMETER Dir
  Where the exe is saved (default: Downloads\Eldenheim, or the fixed drive with the most free space if that drive is
  short of the ~3.5 GB needed). The exe is kept there: run it again later for Maintenance (repair, uninstall).
#>
param(
    [string]$Dir = "",
    [string]$Repo = "glass-vault-studio/eldenheim-private",
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

function Get-GitToken {
    # Ask git's credential helper (Git Credential Manager) for the saved GitHub sign-in. The request goes through a
    # file: Windows PowerShell and .NET can put a byte-order mark in front of piped input, which git rejects.
    $request = Join-Path ([IO.Path]::GetTempPath()) "eldenheim-credential-request.txt"
    [IO.File]::WriteAllText($request, "protocol=https`nhost=github.com`n`n", (New-Object System.Text.UTF8Encoding($false)))
    try { $answer = cmd /c "git credential fill < `"$request`" 2>nul" } finally { Remove-Item $request -ErrorAction SilentlyContinue }
    $line = $answer | Where-Object { $_ -like "password=*" } | Select-Object -First 1
    if (-not $line) { return $null }
    return $line.Substring("password=".Length)
}

function Format-Size([long]$bytes) { "{0:N2} GB" -f ($bytes / 1GB) }

$token = Get-GitToken
if (-not $token) { throw "git has no GitHub sign-in on this PC. Sign in once (for example: git clone https://github.com/$Repo) and run this again." }
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false # asset downloads redirect to storage that must not get the GitHub token
$http = New-Object System.Net.Http.HttpClient($handler)
$http.Timeout = [TimeSpan]::FromHours(6)
$http.DefaultRequestHeaders.UserAgent.ParseAdd("eldenheim-private-install")

function Invoke-Api([string]$url) {
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
    $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("token", $token)
    $req.Headers.Accept.ParseAdd("application/vnd.github+json")
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    $body = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $res.IsSuccessStatusCode) { throw "GitHub said $([int]$res.StatusCode) for $url : $body" }
    return $body | ConvertFrom-Json
}

# The asset's bytes: the API answers with a redirect to a signed storage URL, fetched without the token.
function Open-Asset($asset) {
    $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $asset.url)
    $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("token", $token)
    $req.Headers.Accept.ParseAdd("application/octet-stream")
    $res = $http.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if ([int]$res.StatusCode -ge 300 -and [int]$res.StatusCode -lt 400) {
        $res = $http.GetAsync($res.Headers.Location, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    }
    if (-not $res.IsSuccessStatusCode) { throw "download of $($asset.name) failed: $([int]$res.StatusCode)" }
    return $res.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
}

Write-Host "Eldenheim personal installer - never share it, it contains Elden Ring data." -ForegroundColor Yellow
$release = Invoke-Api "https://api.github.com/repos/$Repo/releases/latest"
$parts = @($release.assets | Where-Object { $_.name -match '\.part\d+$' } | Sort-Object name)
$sums = $release.assets | Where-Object { $_.name -eq "SHA256SUMS.txt" } | Select-Object -First 1
if ($parts.Count -eq 0 -or -not $sums) { throw "the latest release ($($release.tag_name)) has no installer parts" }
$exeName = $parts[0].name -replace '\.part\d+$', ''
$total = ($parts | Measure-Object size -Sum).Sum
Write-Host "Release $($release.tag_name): $exeName, $(Format-Size $total) in $($parts.Count) parts"

$reader = New-Object System.IO.StreamReader(Open-Asset $sums)
$expected = ($reader.ReadToEnd() -split "`n" | Where-Object { $_ -match "\s\*?$([regex]::Escape($exeName))\s*$" } | Select-Object -First 1) -replace '\s.*$', ''
$reader.Dispose()
if (-not $expected) { throw "SHA256SUMS.txt does not list $exeName" }

if (-not $Dir) {
    $Dir = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads\Eldenheim"
    $free = (Get-PSDrive ([IO.Path]::GetPathRoot($Dir).Substring(0, 1))).Free
    if ($free -lt $total + 512MB) {
        $best = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 } | Sort-Object Free -Descending | Select-Object -First 1
        $Dir = Join-Path $best.Root "Eldenheim"
        Write-Host "Not enough room in Downloads; using $Dir"
    }
}
New-Item -ItemType Directory -Force $Dir | Out-Null
$exe = Join-Path $Dir $exeName

$have = (Test-Path $exe) -and ((Get-FileHash $exe -Algorithm SHA256).Hash -ieq $expected)
if ($have) {
    Write-Host "Already downloaded: $exe"
} else {
    $partial = "$exe.download"
    $out = [IO.File]::Create($partial)
    $sha = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] (4MB)
    $done = 0L
    $shown = -1000L
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($part in $parts) {
            $in = Open-Asset $part
            try {
                while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $out.Write($buffer, 0, $n)
                    [void]$sha.TransformBlock($buffer, 0, $n, $null, 0)
                    $done += $n
                    if ($watch.ElapsedMilliseconds - $shown -lt 500) { continue }
                    $shown = $watch.ElapsedMilliseconds
                    $rate = $done / [Math]::Max(1, $watch.Elapsed.TotalSeconds)
                    Write-Progress -Activity "Downloading $exeName" -Status ("{0} of {1}, {2:N1} MB/s" -f (Format-Size $done), (Format-Size $total), ($rate / 1MB)) `
                        -PercentComplete ([int](100 * $done / $total)) -SecondsRemaining ([int](($total - $done) / [Math]::Max(1, $rate)))
                }
            } finally { $in.Dispose() }
        }
        [void]$sha.TransformFinalBlock($buffer, 0, 0)
    } finally { $out.Dispose() }
    Write-Progress -Activity "Downloading $exeName" -Completed
    $hash = -join ($sha.Hash | ForEach-Object { $_.ToString("x2") })
    if ($hash -ine $expected) {
        Remove-Item $partial -Force
        throw "the download is damaged (SHA-256 $hash, expected $expected). Run this again."
    }
    Move-Item $partial $exe -Force
    Write-Host "Downloaded and checked: $exe"
}

if ($NoStart) { Write-Host "Not starting it (-NoStart)."; return }
Write-Host "Starting the installer: check the Valheim folder, tick the box, click Install."
Start-Process $exe

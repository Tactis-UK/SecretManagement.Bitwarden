[CmdletBinding()]
param (
    [string] $Configuration = 'Release',
    [string] $Framework = 'net10.0',
    [string[]] $RuntimeIdentifiers = @('osx-arm64', 'osx-x64', 'linux-x64', 'win-x64'),
    [switch] $Publish,
    [string] $Repository,
    [string] $NuGetApiKey
)

$ErrorActionPreference = 'Stop'

$moduleName = 'SecretManagement.Bitwarden'
$stage = "./dist/$moduleName"

$nativeFiles = @{
    'osx-arm64' = 'libbitwarden_c.dylib'
    'osx-x64'   = 'libbitwarden_c.dylib'
    'linux-x64' = 'libbitwarden_c.so'
    'win-x64'   = 'bitwarden_c.dll'
}

Remove-Item ./build, ./dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path ./build, $stage | Out-Null

foreach ($rid in $RuntimeIdentifiers) {
    if (-not $nativeFiles.ContainsKey($rid)) {
        throw "Unsupported RID: $rid"
    }

    Write-Host "Publishing SDK dependencies for $rid..."

    dotnet publish ./Dependencies/Dependencies.csproj `
        -c $Configuration `
        -f $Framework `
        -r $rid `
        --self-contained false `
        -o "./build/$rid"

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed for $rid"
    }
}

Write-Host "Staging module..."

$excluded = @(
    '.gitignore',
    '.git',
    '.github',
    '.vscode',
    'build',
    'dist',
    'Dependencies',
    'Tests',
    'tests'
)

Get-ChildItem . -Force |
    Where-Object { $_.Name -notin $excluded -and $_.Name -ne 'build.ps1' } |
    Copy-Item -Destination $stage -Recurse -Force

Remove-Item "$stage/lib", "$stage/runtimes" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$stage/lib" | Out-Null

$sdk = Get-ChildItem "./build/$($RuntimeIdentifiers[0])" -Recurse -File -Filter 'Bitwarden.Sdk.dll' | Select-Object -First 1

if (-not $sdk) {
    throw "Could not find Bitwarden.Sdk.dll"
}

Copy-Item $sdk.FullName "$stage/lib/Bitwarden.Sdk.dll" -Force

foreach ($rid in $RuntimeIdentifiers) {
    $nativeFile = $nativeFiles[$rid]
    $native = Get-ChildItem "./build/$rid" -Recurse -File -Filter $nativeFile | Select-Object -First 1

    if (-not $native) {
        throw "Could not find $nativeFile for $rid"
    }

    $runtimePath = "$stage/runtimes/$rid/native"
    New-Item -ItemType Directory -Force -Path $runtimePath | Out-Null
    Copy-Item $native.FullName "$runtimePath/$nativeFile" -Force
}

Test-ModuleManifest "$stage/$moduleName.psd1" | Out-Null

Write-Host "Built module at $stage"

if ($Publish) {
    if (-not $Repository) {
        throw "Missing -Repository"
    }

    $args = @{
        Path       = $stage
        Repository = $Repository
        Force      = $true
    }

    if ($NuGetApiKey) {
        $args.NuGetApiKey = $NuGetApiKey
    }

    Publish-Module @args
}
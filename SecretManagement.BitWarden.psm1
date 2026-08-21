function Import-BitwardenSdk {
    <#
    .SYNOPSIS
    Imports the C# (.NET) version of the Bitwarden SDK into the PowerShell session.
    
    .DESCRIPTION
    Imports the required library files all dependencies for the Bitwarden Secrets SDK into the PowerShell session.
    
    .EXAMPLE
    if(-not $script:BitwardenSdkLoaded){Import-BitwardenSdk}
    #>
    [CmdletBinding()]
    param ()
    if ($script:BitwardenSdkLoaded) { return }

    
    # Define the name of the Bitwarden SDK native library for each supported runtime
    $nativeLibraries = [PSCustomObject]@{
        'linux-x64' = 'libbitwarden_c.so'
        'osx-arm64' = 'libbitwarden_c.dylib'
        'osx-x64' = 'libbitwarden_c.dylib'
        'win-x64' = 'bitwarden_c.dll'
    }

    # Determine the OS and Processor Architecture
    $platform = switch -Wildcard ([System.Runtime.InteropServices.RuntimeInformation]::OSDescription) {
        "*Windows*" { "win" }
        "*Linux*"   { "linux" }
        "*Darwin*"  { "osx" }
        "*macOS*"   { "osx" }
        Default     { throw "The operating system your system is running is not supported by the .NET version of the Bitwarden SDK. Supported operating systems are Windows, MacOS, and Linux." }
    }
    $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        "X64"  { "x64" }
        "Arm64" { "arm64" }
        Default { throw "The processor architecture your system is running is not supported by the .NET version of the Bitwarden SDK. Supported architectures are x64 and arm64." }
    }

    # Determine if the Runtime is supported
    $supportedRuntimes = ($nativeLibraries | Get-Member -MemberType NoteProperty).Name
    $runtime = "$platform-$architecture"
    
    # Verify
    if ($supportedRuntimes -notcontains $runtime) {
        throw "The operating system and processor architecture combination you're running is not a valid runtime for the .NET version of the Bitwarden SDK. Supported runtimes are $($supportedRuntimes -join ', ')."
    }

    # If we got here then the system is running on a supported runtime for the Bitwarden SDK
    $libPath = Join-Path -Path $PSScriptRoot -ChildPath 'lib'
    $sdkPath = Join-Path -Path $libPath -ChildPath 'Bitwarden.Sdk.dll'
    $nativeLibPath = Join-Path -Path $PSScriptRoot -ChildPath "runtimes/$runtime/native/$($nativeLibraries.$runtime)"

    if (-not (Test-Path -Path $libPath)) {
        throw "The 'lib' directory could not be found within this module. We expected it to be located inside '$($PSScriptRoot)'"
    }

    if (-not (Test-Path -Path $sdkPath -ErrorAction SilentlyContinue)) {
        throw "The required Bitwarden.Sdk.dll file could not be found within the '$($libPath)' directory."
    }

    if (-not (Test-Path -Path $nativeLibPath -ErrorAction SilentlyContinue)) {
        throw "The required '$($nativeLibraries.$runtime)' file could not be found at '$nativeLibPath'."
    }

    $sdkTypes = Add-Type -Path $sdkPath -PassThru -ErrorAction Stop
    $sdkAssembly = $sdkTypes[0].Assembly
    $nativeLibPathForResolver = $nativeLibPath

    [System.Runtime.InteropServices.NativeLibrary]::SetDllImportResolver(
        $sdkAssembly,
        {
            param (
                [string] $libraryName,
                [System.Reflection.Assembly] $assembly,
                [System.Nullable[System.Runtime.InteropServices.DllImportSearchPath]] $searchPath
            )

            if ($libraryName -in @('bitwarden_c', 'bitwarden_c.dll', 'libbitwarden_c.so', 'libbitwarden_c.dylib')) {
                return [System.Runtime.InteropServices.NativeLibrary]::Load($nativeLibPathForResolver)
            }

            return [IntPtr]::Zero
        }.GetNewClosure()
    )

    $script:BitwardenSdkLoaded = $true
}
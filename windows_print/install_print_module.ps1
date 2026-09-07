param(
    [Parameter(Mandatory = $true)][string]$CertificatePath,
    [Parameter(Mandatory = $true)][string]$PackagePath
)

$ErrorActionPreference = "Stop"
Import-Certificate -FilePath $CertificatePath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Import-Certificate -FilePath $CertificatePath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
Import-Certificate -FilePath $CertificatePath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null
Add-AppxPackage -Path $PackagePath -ForceApplicationShutdown

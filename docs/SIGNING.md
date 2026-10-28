# Release signing

DaiBan is currently published without a commercial code-signing certificate. This document explains how to sign the native executable and MSI when a certificate becomes available.

## Current state

- `DaiBan.exe` and `TodoDesk-1.3.0-x64.msi` are unsigned.
- Windows may show “Unknown publisher” during installation. The MSI itself is installed by the signed Windows Installer service.
- No certificate, private key, PFX, or password is included in this repository.
- The download page includes SHA-256 checksum files so users can verify the download.

## What is needed

A publicly trusted **code-signing certificate** with a private key:

- Code Signing EKU (`1.3.6.1.5.5.7.3.3`).
- A PFX file for exportable keys, or a hardware token/cloud HSM for higher-assurance certificates.
- A publicly trusted certificate chain. A self-signed certificate is suitable only for local testing and will not remove “Unknown publisher” warnings on other machines.

## Sign the native build

The recommended tool is Microsoft `signtool.exe` from the Windows SDK:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  /f C:\path\to\codesign.pfx /p <password> `
  .\dist\native\DaiBan.exe

signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  /f C:\path\to\codesign.pfx /p <password> `
  .\dist\installer\TodoDesk-1.3.0-x64.msi
```

Verify:

```powershell
signtool verify /pa /v .\dist\native\DaiBan.exe
signtool verify /pa /v .\dist\installer\TodoDesk-1.3.0-x64.msi
```

Build the MSI **after** signing the executable so the signed EXE is inside the package, then sign the MSI.

Do not place the PFX or password in the repository, build scripts, command history, or public issues. For CI, pass them through secret storage and remove any temporary PFX file after signing.

## Smart App Control

A code signature identifies the publisher but does not guarantee that every Smart App Control machine will allow a new application. Smart App Control also considers application reputation and policy. If a user is blocked by their organisation's App Control policy, the correct fix is an administrator-approved allow rule or a trusted signed distribution — not disabling security guidance blindly.

The MSI route is used because the environment's application-control policy blocked standalone setup executables, while the signed Windows Installer service can install the package. This does not remove the need for code signing for public trust.

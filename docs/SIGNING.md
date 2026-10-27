# Release signing

DaiBan does not ship a signing certificate or private key. This document explains what is ready in the repository, what is still needed for a trusted signature, and how to configure it without committing secrets.

## What is already prepared

- `scripts/sign.ps1` signs the three user-facing PowerShell entry points with Authenticode:
  - `app/DaiBan.ps1`
  - `install.ps1`
  - `uninstall.ps1`
- `.github/workflows/release.yml` can sign the files before packaging when these repository secrets exist:
  - `SIGNING_PFX_BASE64` — base64 text of a PFX file containing the private key
  - `SIGNING_PFX_PASSWORD` — the PFX password
- Release assets include a SHA-256 checksum. `.gitignore` excludes PFX, P12, CER, KEY and secrets directories.

## What is needed

A real public release needs a **code-signing certificate**:

- Ideally a publicly trusted OV or EV code-signing certificate. EV certificates may require a hardware token or cloud HSM; those cannot simply be stored as a PFX in GitHub Actions.
- The certificate must include the Code Signing EKU (`1.3.6.1.5.5.7.3.3`) and its private key for signing.
- A self-signed certificate is only suitable for local testing. It will not be trusted by other users.

There is no universally correct certificate vendor choice. Choose a CA that supports the signing model you can use (PFX file vs. hardware token/cloud signing), and verify its Windows/Smart App Control guidance.

## Sign locally

Keep the PFX outside the repository, for example in a temporary folder. Do not place it in the project tree.

```powershell
$env:DAIBAN_PFX_PASSWORD = 'your-pfx-password'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sign.ps1 `
  -PfxPath 'C:\path\to\codesign.pfx'
Remove-Item Env:\DAIBAN_PFX_PASSWORD
```

The password can also be supplied with `-Password`, but an environment variable is less likely to end up in shell history. For a self-signed test certificate add `-AllowUntrusted`; public releases should not use this switch.

Verify any signed script:

```powershell
Get-AuthenticodeSignature .\app\DaiBan.ps1 | Format-List Status, SignerCertificate
```

A signature status of `Valid` means the local certificate chain and hash verify. It does not guarantee Smart App Control reputation on every user's machine.

## Sign in GitHub Actions

Add the secrets under **Repository settings → Secrets and variables → Actions**:

- `SIGNING_PFX_BASE64`
- `SIGNING_PFX_PASSWORD`

Create the base64 value locally:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\to\codesign.pfx')) |
  Set-Clipboard
```

On a `v*` tag, the release workflow:

1. validates the project,
2. optionally decodes the PFX to a temporary runner path and signs,
3. packages the app,
4. publishes the ZIP and checksum.

If no signing secret is configured, releases are produced unsigned. That is intentional. Never commit a PFX or password to make a release “just work.”

## Smart App Control and distribution format

DaiBan is currently hosted by the signed Windows PowerShell runtime rather than distributed as an unsigned executable. That choice lets it run on Windows 11 systems where unsigned local EXEs are blocked. Authenticode-signing the scripts is useful for publisher identity and for environments that enforce script signatures, but it does not automatically give an arbitrary PowerShell project a good application reputation.

If a standalone native `.exe` / `.msi` becomes a goal:

- it needs a native build and a trusted code-signing certificate;
- Smart App Control reputation may need time or a recognized publisher;
- the current script-hosted architecture is not a substitute for that distribution model.

This limitation is better made explicit in the release notes than hidden behind a signing checkbox.

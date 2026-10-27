# Security policy

## Scope

DaiBan is a local-only Windows desktop app. It does not contain a server, account system, telemetry, or network calls. Its data files are plain JSON under `%APPDATA%\DaiBan` or a user-selected folder.

## Reporting

Please report a suspected vulnerability privately through GitHub's **Security advisories → Report a vulnerability** for this repository. Do not open a public issue for a security problem.

Include the affected version, Windows build, reproduction steps, and any relevant files. Please avoid attaching real personal todo data.

## Signing and distribution

The repository does not contain a code-signing certificate or private key. Release signing is optional and documented in [SIGNING.md](SIGNING.md). A signature only proves which publisher signed a file; it is not a substitute for reviewing the source, and it does not guarantee Smart App Control trust on every machine.

Never accept or share PFX files, private keys, or passwords in an issue, pull request, or chat. If a secret is accidentally committed, revoke/rotate it with the certificate issuer immediately; deleting the commit is not enough.

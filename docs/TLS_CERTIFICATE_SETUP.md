# TLS certificate setup for Windows

This document describes the certificate checks used by the `auth_probe` laboratory application for the MAX TCP/TLS endpoint `api2.oneme.ru:443`.

## Trust model

The application does not disable certificate validation and does not accept arbitrary certificates presented by the server.

It uses two pinned certificates:

| Certificate | Purpose | Windows store | SHA-1 | SHA-256 |
|---|---|---|---|---|
| Russian Trusted Root CA | Trust root | `CurrentUser\\Root` | `8FF915CCAB7BC16F8C5C8099D53E0E115B3AEC2F` | `D26D2D0231B7C39F92CC738512BA54103519E4405D68B5BD703E9788CA8ECF31` |
| Russian Trusted Sub CA 2024 | Issuing intermediate used by the MAX endpoint | `CurrentUser\\CA` | `6741AB02CF6598C09652DC34D2DC095904E32B52` | `2155785036C900DBB5F1BB2A1569C80C55595BD6BF94867A29BBDDBC7D88A3F2` |

The old generic `russian_trusted_sub_ca_pem.crt` is a different, older intermediate (2022). It must not be substituted for the 2024 certificate presented in the observed MAX chain.

## Download sources

- Root PEM: https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt
- Official Sub CA archive: https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.zip
- Official certificate information page: https://www.gosuslugi.ru/crt

The application extracts the specifically named 2024 PEM certificate from the official Sub CA archive and validates both SHA-1 and SHA-256 against the constants in `WindowsCertificateManager`. The downloaded file is not trusted merely because it came from a TLS connection or has a matching display name.

The official archive URL is an HTTPS endpoint. If its layout or certificate filenames change, the download must fail closed until the new artifact is inspected and its fingerprint is independently verified. Do not fall back to the older 2022 certificate.

## Validation performed before use

For each certificate the application:

1. Downloads only from the configured official source, with redirects disabled and a size limit.
2. Parses the PEM certificate and checks the pinned SHA-1 and SHA-256 fingerprints.
3. Uses Windows CryptoAPI to inspect Subject, Issuer, validity dates, Basic Constraints and Key Usage.
4. Requires CA=true and KeyCertSign.
5. Verifies that the intermediate chain terminates at the pinned Root CA and that no unexpected chain status remains.
6. Rejects expired or not-yet-valid certificates.

The root must be self-issued. The intermediate must identify the pinned Root CA as its issuer.

## Installation behavior

Installation is a separate user action for each certificate and requires explicit confirmation in the UI.

- Root is added only to the current user's `Root` store.
- Intermediate is added only to the current user's `CA` store.
- A certificate present only in `LocalMachine` is reported separately; it does not suppress installation into `CurrentUser`.
- The app verifies that the certificate is present in the intended current-user store after installation.

No administrator elevation is requested. The application must never install the leaf certificate for `*.oneme.ru` as a root or intermediate CA.

## TLS checks in auth_probe

The certificate panel exposes separate operations:

- Inspect Root CA.
- Install Root CA.
- Inspect Intermediate CA.
- Install Intermediate CA.
- Test the platform/default Dart TLS context.
- Test the MaxAI context with the pinned Russian certificates.

After a successful installation, both TLS checks run again. Each check connects to `api2.oneme.ru:443` using normal TLS certificate and hostname validation. No `badCertificateCallback`, insecure context, or equivalent bypass is permitted.

The MaxAI context retains platform roots and adds only the pinned Root and the independently verified, pinned 2024 issuing certificate. The intermediate is accepted because its exact certificate bytes are pinned and its issuer chain is verified against the pinned root before it is loaded.

## Remaining release validation

The following checks require execution on Windows and cannot be established by repository inspection alone:

- Run `flutter analyze` and `flutter test` from `apps/auth_probe`.
- Run both TLS checks on a Windows profile with neither certificate preinstalled.
- Install Root and Intermediate separately, confirming the exact target stores.
- Confirm the platform/default TLS result before and after installation.
- Confirm the MaxAI pinned-context result before and after installation.
- Repeat on a clean Windows machine or clean user profile.
- Test expired, modified, wrong-issuer and wrong-fingerprint certificate files and confirm fail-closed behavior.

Do not close Issue #1 until these Windows runtime checks have been reported and reviewed.

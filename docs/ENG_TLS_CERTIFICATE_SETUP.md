# Windows TLS Certificate Setup

This document describes the certificate checks used by the `auth_probe` laboratory application for the MAX TCP/TLS endpoint `api2.oneme.ru:443`.

## Trust model

The application does not disable certificate validation and does not accept arbitrary certificates presented by the server.

It uses two certificates with pinned fingerprints:

| Certificate | Purpose | Windows store | SHA-1 | SHA-256 |
|---|---|---|---|---|
| Russian Trusted Root CA | Trust root | `CurrentUser\\Root` | `8FF915CCAB7BC16F8C5C8099D53E0E115B3AEC2F` | `D26D2D0231B7C39F92CC738512BA54103519E4405D68B5BD703E9788CA8ECF31` |
| Russian Trusted Sub CA 2024 | Issuing intermediate used by the MAX endpoint | `CurrentUser\\CA` | `6741AB02CF6598C09652DC34D2DC095904E32B52` | `2155785036C900DBB5F1BB2A1569C80C55595BD6BF94867A29BBDDBC7D88A3F2` |

The generic `russian_trusted_sub_ca_pem.crt` file is a different, older intermediate certificate (2022). It must not be substituted for the 2024 certificate present in the observed MAX chain.

## Download sources

- Root PEM: https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt
- Official Sub CA archive: https://gu-st.ru/content/lending/russian_trusted_sub_ca_pem.zip
- Official certificate information page: https://www.gosuslugi.ru/crt

The application extracts the specifically named 2024 PEM certificate from the official archive and validates its SHA-1 and SHA-256 fingerprints against the constants in `WindowsCertificateManager`. A downloaded file is not trusted merely because it was obtained over TLS or has a matching display name.

The official archive URL uses HTTPS. If the archive layout or certificate filenames change, the download must fail closed until the new artifact has been inspected and its fingerprint independently verified. Do not use the older 2022 certificate as a fallback.

## Validation before use

For each certificate, the application:

1. Downloads the file only from the configured official source, with redirects disabled and a size limit.
2. Parses the PEM certificate and checks the pinned SHA-1 and SHA-256 fingerprints.
3. Uses Windows CryptoAPI to inspect Subject, Issuer, validity dates, Basic Constraints and Key Usage.
4. Requires `CA=true` and `KeyCertSign`.
5. Verifies that the intermediate certificate chain terminates at the pinned Root CA and contains no unexpected chain status.
6. Rejects expired certificates and certificates that are not yet valid.

The root certificate must be self-issued. The intermediate certificate's Issuer must match the pinned Root CA.

## Installation

Installing each certificate is a separate user action and requires explicit confirmation in the UI.

- The Root certificate is added only to the current user's `Root` store.
- The Intermediate certificate is added only to the current user's `CA` store.
- If a certificate exists only in `LocalMachine`, the application reports that separately. Its presence does not suppress installation into `CurrentUser`.
- After installation, the application verifies that the certificate exists in the intended current-user store.

Administrator elevation is not requested. The application must never install the leaf certificate for `*.oneme.ru` as a root or intermediate CA.

## TLS checks in auth_probe

The certificate panel provides separate operations:

- Inspect Root CA.
- Install Root CA.
- Inspect Intermediate CA.
- Install Intermediate CA.
- Test the platform/default Dart TLS context.
- Test the MaxAI context with the pinned Russian certificates.

After a successful installation, both TLS checks run again. Each check connects to `api2.oneme.ru:443` with normal TLS certificate and hostname validation. Using `badCertificateCallback`, an insecure context or an equivalent bypass is prohibited.

The MaxAI context retains platform root certificates and additionally includes only the pinned Root CA and the independently verified, pinned 2024 intermediate certificate. The intermediate is accepted because its exact bytes are pinned and its Issuer chain is verified against the pinned root before it is loaded.

## Remaining release validation

The following checks must be performed on Windows. They cannot be confirmed by repository inspection alone:

- Run `flutter analyze` and `flutter test` from `apps/auth_probe`.
- Run both TLS checks in a Windows profile where neither certificate is initially installed.
- Install Root and Intermediate separately and confirm the exact target stores.
- Check the platform/default TLS result before and after installation.
- Check the MaxAI pinned-context TLS result before and after installation.
- Repeat the checks on a clean Windows installation or clean user profile.
- Test expired and modified certificates, certificates with an incorrect Issuer and certificates with incorrect fingerprints; verify that the application rejects them in every case.

Do not close Issue #1 until reports from these Windows runtime tests have been provided and reviewed.

# Read-only MAX API Probe

This document records the first read-only API surface implemented in
`packages/maxai_protocol` and exposed by the Windows `apps/auth_probe`
application.

The implementation is based on payload builders and service methods inspected
in the current PyMax source. PyMax is a reverse-engineered reference, not an
official MAX protocol specification. Every method still requires a live
account test before it is considered verified against the server.

## Implemented operations

| Operation | Opcode | Request payload | Response field |
|---|---:|---|---|
| Profile snapshot | LOGIN / LOGIN2 | No additional request | `profile` |
| Contacts snapshot | LOGIN / LOGIN2 | No additional request | `contacts` / `contactInfos` |
| Contact information | 32 | `contactIds: [int]` | `contacts` |
| Chats list | 53 | `marker: int` | `chats` |
| Chat information | 48 | `chatIds: [int]` | `chats` |
| Chat members | 59 | `type: MEMBER, chatId, marker, count` | `members, marker` |
| Chat history | 49 | `chatId, forward, backward, backwardTime, forwardTime, getChat, from, itemType, getMessages, interactive` | `messages` |
| Specific messages | 71 | `chatId, messageIds: [int]` | `messages` |

Profile and contact snapshots are read from the already received LOGIN/LOGIN2
bootstrap result. They do not generate another network request.

## Important opcode distinction

Opcode 16 (`PROFILE`) is used by the inspected PyMax implementation to change
the current profile. It is not a profile-read operation and is deliberately
excluded from the read-only API.

Opcode 36 (`CONTACT_LIST`) appears in the opcode enum, but the inspected PyMax
source does not provide a corresponding list payload/service method. It is
therefore not sent until its request schema and semantics are independently
confirmed. Contact details are currently fetched through opcode 32 using
`contactIds`.

## Safety and diagnostics

- The API layer accepts only RESPONSE frames matching the requested opcode.
- ERROR frames become a safe exception; the raw server payload is not copied
  into the exception or diagnostic log.
- API Probe logs operation name, elapsed time, counts and safe errors.
- Message text, contact details, tokens and raw response payloads are not
  written to the journal.
- No write operations are included in this API surface.
- The UI exposes independent buttons and requires an authenticated session.

## Unit test coverage

The `max_read_only_api_test.dart` tests cover:

- exact opcodes and request payloads for all six network read-only operations;
- profile and contact snapshots from LOGIN without an additional request;
- successful and empty collection parsing;
- safe handling of ERROR frames;
- rejection of RESPONSE frames with a mismatched opcode;
- rejection of malformed response structures;
- pending-request cleanup after a timeout;
- completion of pending requests when the connection closes;
- invalid IDs rejected before a request is sent.

These tests use a fake transport. They verify client-side behavior but are not
live tests against the MAX server.

## Local verification

From `packages/maxai_protocol`:

```powershell
dart analyze
dart test
```

From `apps/auth_probe`:

```powershell
flutter analyze
flutter test
```

Specific message lookup (MSG_GET) uses the selected Chat ID and a comma-,
semicolon- or whitespace-separated list of Message IDs. It is read-only.

Live API checks should be performed one operation at a time in the
`auth_probe` UI. A passing unit test verifies payload construction and
response handling, not server-side availability or account permissions. Record
each live-check status separately after observing the actual server result.

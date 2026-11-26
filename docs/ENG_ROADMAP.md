# MaxAI Roadmap

> Core principle: research and validate the MAX protocol in the separate `apps/auth_probe` application first, then complete the `maxai_protocol` library, and only after that begin full MaxAI application development.

Statuses in this document describe the plan and do not automatically prove that a feature works. A task is complete only after implementation, validation, and documentation updates.

## Stage 1. MAX protocol research

**Goal:** establish a verified technical description of the protocol and its behavior.

- [x] Research frame structure and basic protocol framing.
- [x] Implement the basic TCP/TLS and WebSocket transports.
- [x] Implement session initialization and Heartbeat.
- [x] Implement the primary QR and SMS authentication flows.
- [x] Implement two-factor authentication handling.
- [x] Implement LOGIN/LOGIN2 and session restoration.
- [x] Implement local protected token storage using Windows DPAPI.
- [x] Implement local Logout.
- [ ] Validate all implemented flows with a real account.
- [ ] Compare request and response formats with PyMax.
- [ ] Separate confirmed facts, assumptions, and unknown behavior.
- [ ] Update `MAX_Protocol_Specification.md` based on validation results.

## Stage 2. Windows TLS and certificates

**Goal:** provide secure TLS connections on different Windows computers, including systems without preconfigured certificate stores.

- [x] Add diagnostics for Russian Trusted Root CA.
- [x] Implement separate checks and installation actions for Root CA and Intermediate CA.
- [x] Implement root certificate fingerprint verification.
- [x] Find and confirm the current official source for the Intermediate CA.
- [x] Verify certificate signatures, trust chain, CA purpose, and validity periods.
- [x] Download certificates only from verified sources.
- [x] Require explicit user consent before installation.
- [x] Install Root CA into `CurrentUser\\Root` and Intermediate CA into `CurrentUser\\CA`.
- [x] Verify installation results and repeat TLS connections.
- [x] Validate the workflow on a clean Windows environment without preinstalled certificates.
- [ ] Test expired, substituted, and invalid certificates.
- [x] Ensure that TLS certificate validation is never bypassed.

**Status:** completed for the supported installation and connection scenarios. Adversarial certificate-negative testing remains a separate hardening task.

## Stage 3. MAX read-only API

**Goal:** implement and verify retrieval of MAX data without changing account state.

- [x] Obtain the profile snapshot from LOGIN/LOGIN2.
- [x] Obtain the contacts snapshot from LOGIN/LOGIN2.
- [x] CONTACT_INFO (32).
- [x] CHATS_LIST (53).
- [x] CHAT_INFO (48).
- [x] CHAT_MEMBERS (59).
- [x] CHAT_HISTORY (49).
- [x] MSG_GET (71).
- [ ] Validate all implemented operations against a real account.
- [ ] Verify pagination for message history and chat members.
- [ ] Implement typed contact, chat, message, and member models.
- [ ] Research and add further read-only methods only after validating their payloads and semantics.
- [ ] Add tests for valid, empty, incomplete, and erroneous responses.
- [ ] Verify safe handling of personal data and secrets in logs.

## Stage 4. auth_probe test application

**Goal:** turn the separate Windows application into a reproducible protocol testing laboratory. It is not the main MaxAI application.

- [x] Separate QR and SMS authentication flows.
- [x] Diagnostic log.
- [x] Separate certificate inspection and installation actions.
- [x] Separate buttons for implemented read-only API operations.
- [ ] Display structured and safely filtered results for each check.
- [ ] Display TCP, TLS, WebSocket, session, and authentication states.
- [ ] Allow individual checks to be rerun without re-authentication where supported.
- [ ] Add diagnostic log export with secrets and personal data masked.
- [ ] Add error, timeout, connection-loss, and recovery test scenarios.
- [ ] Validate the application on multiple Windows configurations.

## Stage 5. Complete the maxai_protocol library

**Goal:** deliver a stable standalone Dart library independent of the auth_probe UI.

- [ ] Complete and document the transport layer.
- [ ] Complete session, authentication, and restoration management.
- [ ] Unify error handling, timeouts, and connection shutdown.
- [ ] Add typed models and verified read-only APIs.
- [ ] Test concurrent requests, response correlation, and frame ordering.
- [ ] Test reconnection and recovery after network failures.
- [ ] Prepare public API documentation and usage examples.
- [ ] Pass `dart analyze` and `dart test` in the supported CI environment.
- [ ] Tag stable library version 1.0.0.

## Stage 6. Main MaxAI application

**Goal:** build the full MAX client on top of the verified library.

- [ ] Design the application architecture and layer boundaries.
- [ ] Build the authentication and account management UI.
- [ ] Implement the chat list and conversation viewer.
- [ ] Implement history loading and contact management.
- [ ] Implement message sending after separate research and validation of the relevant protocol operations.
- [ ] Implement attachments and media.
- [ ] Implement settings, secure data storage, and connection recovery.

## Stage 7. AI features and Bitrix24 integration

**Goal:** combine MAX conversation history, Bitrix24 CRM data, and AI analysis to build an up-to-date customer communication queue and help prepare personalized messages.

### 7.1. Bitrix24 integration

- [ ] Research the REST API and available Bitrix24 authentication methods.
- [ ] Implement connection to a Bitrix24 portal.
- [ ] Implement secure storage and renewal of integration credentials.
- [ ] Retrieve CRM contacts and companies.
- [ ] Retrieve deals and their linked contacts.
- [ ] Retrieve responsible employees.
- [ ] Retrieve tasks, activities, and scheduled activities.
- [ ] Determine which CRM fields and entities are the source of the next-contact/message date.
- [ ] Retrieve scheduled communication dates and times, accounting for the portal time zone.
- [ ] Handle changes, rescheduling, cancellation, and completion of tasks/activities.
- [ ] Respect user access permissions and REST API limits.

### 7.2. Matching MAX and CRM contacts

- [ ] Design a strategy for matching MAX contacts with Bitrix24 contacts/companies.
- [ ] Use available identifiers and normalized contact data with privacy safeguards.
- [ ] Store confirmed MAX ID ↔ Bitrix24 entity ID links.
- [ ] Handle ambiguous matches through manual confirmation.
- [ ] Prevent duplicate records and incorrect links between different customers.
- [ ] Revalidate links when CRM data changes.

### 7.3. Queue of contacts to message

- [ ] Build a unified contact queue from Bitrix24 tasks and scheduled activities.
- [ ] Show the contact, company, deal, and responsible manager.
- [ ] Show the date and time of the next scheduled communication.
- [ ] Distinguish upcoming, overdue, cancelled, and completed communications.
- [ ] Account for rescheduled deadlines and CRM changes.
- [ ] Identify contacts without a scheduled next-contact date where required by the CRM workflow.
- [ ] Support filtering and sorting by date, priority, owner, and status.

### 7.4. AI analysis and message preparation

- [ ] Analyze available MAX conversation history for the selected contact.
- [ ] Include related Bitrix24 deals, tasks, notes, and activities.
- [ ] Build customer context and a history of agreements.
- [ ] Determine priority and recommend the next communication step.
- [ ] Identify overdue and potentially outdated communications.
- [ ] Generate a personalized message draft using CRM and conversation context.
- [ ] Explain recommendations and show the data sources used.
- [ ] Allow the user to edit and approve the message.

### 7.5. Sending and execution tracking

- [ ] Send messages through verified MAX protocol methods.
- [ ] Require user confirmation before sending by default.
- [ ] Confirm sending from the MAX operation result, not merely from a button click.
- [ ] Link the send result to the originating Bitrix24 task/activity.
- [ ] Update CRM completion status only after the result is confirmed and according to agreed rules.
- [ ] Prevent duplicate sends when processing the same task more than once.
- [ ] Handle send errors, timeouts, and uncertain outcomes without falsely marking a message as sent.
- [ ] Maintain a synchronization and user-action log.

## Stage 8. Release and maintenance

**Goal:** prepare the application for stable use.

- [ ] Prepare a Windows installer.
- [ ] Implement secure application updates.
- [ ] Configure automated builds and tests.
- [ ] Validate installation and first launch on a clean Windows system.
- [ ] Prepare user and technical documentation.
- [ ] Release the first stable version of MaxAI.

---

## Stage completion criteria

- Implementation is covered by tests and, where a real server is required, practical validation.
- Unknown protocol or API behavior is not presented as confirmed.
- Secrets and personal data do not appear in diagnostic logs.
- Errors and uncertain outcomes are handled explicitly.
- Documentation matches actual implementation behavior.

## Architectural principles

1. `auth_probe` remains a separate test application.
2. `maxai_protocol` does not depend on Flutter UI or CRM business logic.
3. Bitrix24 integration is implemented as a separate module and is not mixed with MAX transport/API code.
4. Bitrix24 is the source of CRM contacts, tasks, and planned communication dates; MAX is the source of conversation facts and message statuses.
5. AI analyzes the combined context and proposes actions, but does not replace CRM or MAX facts with assumptions.
6. Message sending and CRM data changes are controlled, require user confirmation, and verify the outcome.

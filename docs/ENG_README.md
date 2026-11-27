[RU](README.md) | [ENG](ENG_README.md)

# MaxAI Documentation

Russian is the project's default documentation language. Russian documents are the authoritative source versions. English translations are stored in separate Markdown files prefixed with `ENG_`.

## Language convention

- **RU by default:** a file without the `ENG_` prefix contains the Russian version.
- **ENG:** the English translation uses the same base filename with the `ENG_` prefix.
- For example, `ROADMAP.md` is the Russian source and `ENG_ROADMAP.md` is its English translation.
- New documents are created in both languages from the start.
- Whenever a Russian source document changes, its English translation must be reviewed and updated in the same change.
- The English version must preserve the structure, technical meaning, statuses, examples, tables and warnings of the Russian source.
- API names, opcodes, class names, methods, variables, protocol fields, commands and file paths are not translated.
- If a translation is not yet synchronized, this must be stated explicitly in both documents.

## Documents

| Topic | Russian source | English translation |
|---|---|---|
| MAX protocol specification | [MAX_Protocol_Specification.md](MAX_Protocol_Specification.md) | Translation in progress |
| Development workflow and VS Code | [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) | [ENG_DEVELOPMENT_WORKFLOW.md](ENG_DEVELOPMENT_WORKFLOW.md) |
| Read-only API Probe | [READ_ONLY_API_PROBE.md](READ_ONLY_API_PROBE.md) | [ENG_READ_ONLY_API_PROBE.md](ENG_READ_ONLY_API_PROBE.md) |
| Roadmap | [ROADMAP.md](ROADMAP.md) | [ENG_ROADMAP.md](ENG_ROADMAP.md) |
| Windows TLS certificate setup | [TLS_CERTIFICATE_SETUP.md](TLS_CERTIFICATE_SETUP.md) | [ENG_TLS_CERTIFICATE_SETUP.md](ENG_TLS_CERTIFICATE_SETUP.md) |

## Update procedure

1. Make and verify changes in the Russian source document.
2. Update the English translation while preserving section and technical-detail parity.
3. Check cross-document links and keep the table above current.
4. Include both language versions in the same pull request/commit whenever a documentation change affects their content.

The Russian version takes precedence when resolving discrepancies. The English translation must not introduce technical claims absent from the source.

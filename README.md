# Bách SMS iOS 1.0.2 — Native fixes

Based on v1.0.1, retaining its local storage key and original recipient/compose/review flow.

- Present MFMessageComposeViewController with UIKit present/dismiss and full-screen bounds. End editing before presentation; deliver cancel/send/fail only after dismissal completes.
- Import files with a native document picker in copy mode, then make a coordinated local copy before background parsing. Allows selection from Files and third-party providers; validates xlsx/csv/tsv on import.
- Read inline/shared/rich-text Excel cells, skip blank cover sheets, fix AA+ column indexes, support numeric/scientific phone cells, and accept phone-only headers.
- Parse Windows CRLF, UTF-8 BOM, UTF-16, semicolon CSV and TSV. Deduplicate phones and report newly added recipients accurately.
- Build IPA in GitHub Actions after six Swift regression tests. SMS send/cancel and keyboard alignment require an iPhone with a SIM for final validation.

Old binary .xls files must be saved as .xlsx before import. This app requires the user to tap Send for each message. Existing saved data is retained with the same bundle identifier and UserDefaults key.

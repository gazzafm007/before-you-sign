# Before You Sign

ARPRA Limited's pre-purchase document checker for people buying a home in a NSW land lease community.

The buyer scans or attaches the Disclosure Statement, Residential Site Agreement, Community Rules and any contract for the home. The app sends them to Claude with ARPRA's checking instructions (`lib/prompt.dart`) and shows a plain-English report covering:

- an overall concern rating
- costs and a projection of the site fee
- key dates, including the earliest signing date and the cooling-off period
- red, amber and green items, each with the clause and the question to ask
- blank fields
- questions for the operator

The report can be shared as a PDF. "Get ARPRA to review" sends the documents and report to ARPRA after payment (Stripe Payment Link).

**Status:** test build 0.1 (Android). It is not for public release.

## Test build notes

- **Claude API key:** entered in the app's Settings and stored only on the phone. Use a key from a separate "Before You Sign" workspace with a spend limit. Never commit a key to this repository.
- **Default model:** `claude-opus-5-5`. Sonnet can be chosen in Settings.
- **Payments:** the Stripe Payment Link, the fee text and the ARPRA email address are all set in Settings. The app adds the case reference to the payment link as `client_reference_id`.
- **Hand-off:** in the test build this is an email from the phone (via flutter_email_sender) with the report PDF, each document as a PDF, and a JSON case file attached.

## Build

Requires Flutter 3.47 or later.

```
flutter pub get
flutter build apk --release --split-per-abi
# install: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The release build is signed with the debug key, which is fine for sideloading. Use the ARPRA upload key before any Play Store release.

## Code map

| File | Purpose |
| --- | --- |
| `lib/prompt.dart` | Checking instructions (law, checklist, JSON output shape); version stamped into each report as `_prompt_version` |
| `lib/standard_form.dart` | The prescribed standard form of site agreement (FT6571 Sep 2024), sent with every check for a word-for-word comparison. Replace it if Fair Trading issues a new version |
| `lib/analyzer.dart` | Photo resizing, Claude API call (streaming), report parsing |
| `lib/models.dart` | Cases, documents, local storage |
| `lib/report_pdf.dart` | PDF report, and scanned pages to PDF |
| `lib/sample.dart` | Built-in sample report (fictional community) |
| `lib/screens/` | Home, documents, progress, report, ARPRA review, settings |

## Plan

Pricing, the server hand-off (check.php and request.php on ARPRA's cPanel hosting), Stripe Checkout and webhook, membership, and marketing are covered in the plan document: https://claude.ai/artifact/VnLBzLkX3S8Fd7VTMpPmYk

## Next steps

1. Test against past cases and send the exported reports (PDF + data) for review.
2. Tune `lib/prompt.dart` from the results.
3. Build the server version so the API key moves off the phone.
4. Set up Stripe test mode, then the webhook.
5. Pilot with real buyers. Then publish to Play Store, followed by iPhone via Codemagic.

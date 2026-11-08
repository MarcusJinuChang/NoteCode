<!-- Draft for the public repo (docs/refactor/split.md › S3). scripts/export-public.sh
     copies it to the export's SECURITY.md. -->

# Security

## Reporting a vulnerability

Please report a vulnerability privately, not in a public issue: use GitHub's
**Report a vulnerability** button on this repository's Security tab, or mail
notecodesupport@gmail.com with "Security" in the subject.

Say what is affected, how to reproduce it, and what an attacker could do with
it. You will get an answer within a week. A fix goes into the next release,
and you are credited in it unless you would rather not be.

## What is in scope

- The app in this repository: the editor, storage, import and export
  (Markdown, PDF, files dropped or shared in), and the links it opens.
- The App Store build of NoteCode, for anything that comes from this code.

The App Store edition's own parts (the subscription, the run service and its
proxy, ads) are not in this repository, but reports about them are welcome by
the same routes.

## What the app does with data

Notes are stored on the device with SwiftData and are not sent anywhere by
this edition. Run opens a free online compiler site in the browser, with the
block's code either in the link (Compiler Explorer) or on the pasteboard
(Programiz); that happens only when you press Run. Send Feedback opens a mail
you write and send yourself.

## Supported versions

Only the newest release, and `main`, get fixes.

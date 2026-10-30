# NoteCode Privacy Policy

_Last updated: 10/30/26_

NoteCode is a note-taking app for computer science coursework. It has no
account and no analytics, and your notes are never uploaded. Three things do
leave your iPad, each described below: running code in the app (NoteCode Pro),
the ads shown to readers without Pro, and the sites you choose to open.

## What stays on your device

Your notes, drawings, folders and settings are stored on your iPad and nowhere
else. They are not uploaded to us or to anyone. NoteCode does not use iCloud
or any sync service.

If you back up your iPad with iCloud or a computer, the system includes
NoteCode's data in that backup, as it does for any app. That is Apple's
service, under Apple's terms.

The AI features (Explain Code, Summarise Note) use Apple's on-device model.
Your text is not sent anywhere for them.

## Running code in the app (NoteCode Pro)

When a reader with NoteCode Pro taps Run and the destination is "In NoteCode",
the code block's text, the input you typed for it and its language are sent
over HTTPS to NoteCode's run service, which passes them to Judge0, an online
code-execution service, to be compiled and run. The result (output and
errors) comes back to the app. Nothing is sent until you tap Run, and your
other notes are never sent. The first time, the app says this before
sending anything, and nothing is sent unless you choose Run.

- **Our run service** (hosted on Cloudflare) does not store your code, input
  or output. It keeps only counts: how many runs a subscription has made today
  and how many requests an address has made this minute, which it drops
  when the day or minute ends. Cloudflare, as the host, handles the connection
  and sees the requesting IP address, under its own privacy policy.
- **Along with each run** the app sends proof of your Pro subscription (the
  signed transaction the App Store gives the app). The service checks it with
  Apple's certificates and uses only its opaque subscription number to count
  runs. It is not linked to your name, email or Apple ID.
- **Judge0** receives the code and input to run them. Judge0 may keep
  submissions on its servers for a time we do not control, so do not put
  passwords, keys or other secrets in a code block you run. Judge0's privacy
  policy applies to what it keeps.

Readers without Pro have no in-app Run. For them, and for anyone who picks a
different destination, Run does the following instead.

- **Run on an online compiler.** Tapping Run opens a compiler site in your
  browser: Compiler Explorer, Programiz or OnlineGDB, or a site you entered
  yourself. For some sites the block's code is placed in the link, so it is
  sent to that site; for the others it is copied to your clipboard and you
  paste it there. The site that gets it is the one you chose in Settings or
  for that folder or note. Nothing is sent until you tap Run. Each site has its
  own privacy policy.

## Ads (readers without Pro)

NoteCode shows banner ads to readers without Pro, through Google AdMob. Pro
removes the ads, and then no ad request is made.

Google's SDK in the app may collect, and use to show and measure ads, a device
identifier and advertising data (including the advertising identifier, if you
allow tracking), how you interact with ads, diagnostic and performance
information such as crashes, and your approximate location, taken from your
IP address. None of it is linked to your name or account, and we do not
receive it. Google's own policy describes it
(https://policies.google.com/technologies/partner-sites).

- **Your choice.** Where the law requires it (the EEA and UK), a consent
  message from Google appears the first time ads would load, and lets you
  accept or decline personalised ads. After that, iPadOS asks whether
  NoteCode may track you across apps and websites. If you decline, you still
  see ads, but they are not personalised and the advertising identifier is not
  used. You can change the tracking permission at any time in iPadOS Settings ›
  Privacy & Security › Tracking, and your answer to Google's message in
  NoteCode's Settings › Help and About › Ad Privacy Options (shown where the
  law requires it), or remove the ads by subscribing to Pro.
- **No ads, no data.** NoteCode does not show ads, or start Google's SDK, for
  readers with Pro. The notes, drawings and code you write are never given
  to the ad SDK.

## Other things that leave your device, only when you ask

- **Links in a note.** Tapping a link opens it in your browser.
- **Share, Export and Print.** Sharing a note, exporting notes or printing
  hands the file to the app or place you pick in the system's share sheet.
- **Subscriptions and tips.** Purchases are handled by Apple. We receive
  nothing about you from them.

## Photos and files

If you insert a photo into a drawing, NoteCode reads only the photo you
choose, through the system's photo picker. NoteCode cannot see the rest of your
library. Importing a file reads only the file you pick.

## Children

NoteCode is not directed at children under 13, and we do not knowingly
collect personal information from them. Ads are general-audience.

## Changes

If this changes, this page will say so, with the date above, before an update
that changes it is released.

## Contact

changm2608@gmail.com

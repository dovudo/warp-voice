# Warp Voice

**Push-to-talk dictation for macOS, using the voice transcription available in your existing Warp account.** Hold the physical backtick / `ё` key, speak, and release it to insert the resulting text into the app you're using.

This is an independent, experimental project. It is **not affiliated with or supported by Warp or Wispr**. It uses undocumented internal interfaces, which can change or stop working. Warp's [voice documentation](https://docs.warp.dev/agents/local-agents/interacting-with-agents/voice/) says transcription is powered by Wispr Flow and subject to anti-abuse limits. There is no separate subscription or API key to configure in this app, but you need a working Warp account with voice access; Warp's own terms, eligibility and limits still apply.

## What it does

- Runs as a small macOS menu-bar app: 🎙 ready, 🔴 recording, ⏳ transcribing.
- Hold the physical backtick / `ё` key for about 0.3 seconds to start recording, then release it to transcribe. A short press still types the key normally.
- Detects the spoken language automatically.
- Copies the transcript to the clipboard and attempts to paste it into the original foreground app. If the active app changes, or a known focused field changes, it keeps the text on the clipboard instead.
- Uses the existing Warp login stored in macOS Keychain. You do not need to create an API key.

The app does not restore the previous clipboard contents. When macOS cannot expose the focused field, it can only check that the same app is still active; changing fields within that app while a request is running may paste into the new field. Secure input fields and apps that reject simulated paste may not work. macOS does not reliably confirm whether the target accepted Cmd+V; if nothing appears, paste the transcript manually.

## Requirements

- macOS, with Xcode Command Line Tools (`xcode-select --install`), Swift, Python 3 and the macOS `security` and `strings` tools.
- Warp installed at `/Applications/Warp.app` and signed into a session with working voice input.
- Internet access and microphone, Accessibility, and potentially Input Monitoring permissions for Warp Voice.
- The current implementation depends on Warp's Stable bundle ID and Keychain entry; Preview or alternate installations may not work.

## Build and install

```sh
git clone https://github.com/dovudo/warp-voice.git
cd warp-voice
./build.sh
open "build/Warp Voice.app"
```

The build produces an ad-hoc signed app. To make it easier to locate in System Settings, move the built `Warp Voice.app` from `build/` to `/Applications` using Finder, then open that copy. If macOS blocks the first launch, use its standard Open Anyway option in Privacy & Security.

1. Grant microphone access when prompted.
2. In **System Settings → Privacy & Security → Accessibility**, add and enable **Warp Voice**. Grant **Input Monitoring** too if macOS requests it.
3. Click the menu-bar microphone and select **Проверить разрешения** (“Check permissions”). macOS may require an app restart.
4. Focus a text field, hold the backtick / `ё` key, speak, then release it. Wait for processing to finish.

A Keychain prompt may ask you to allow access to Warp's saved session. Rebuilding the ad-hoc signed app can cause macOS to request permissions again. The app does not currently start automatically at login.

## How it works

The app records a temporary mono 16 kHz, 16-bit WAV with `AVAudioRecorder`. A local Python helper reads the Warp `User` Keychain entry, uses its refresh token with Firebase's token endpoint, and sends base64 audio and the refreshed ID token to Warp's internal `/ai/transcribe` endpoint with the `wispr` provider. The returned text is placed on the clipboard and pasted with a simulated Cmd+V.

The helper reads Warp's Firebase client identifier from the installed app. Authentication tokens are processed in memory and are not intentionally written to this project's logs or files. The temporary WAV is removed after processing; a crash or forced quit may leave it in the system temporary directory. Diagnostic logs in `~/Library/Application Support/WarpVoice/diagnostic.log` contain stages, status and sizes, but not audio, transcripts or tokens.

**Privacy:** audio leaves your computer and is processed through Warp and its transcription provider; see [Warp's voice privacy description](https://docs.warp.dev/agents/local-agents/interacting-with-agents/voice/). This app uses your Warp session credentials with substantial account access, so review the source before granting Keychain access. Don't share logs, recordings or credentials without checking their contents.

## Current limitations

- macOS only; experimental personal-use prototype, not a production release.
- It relies on undocumented Warp internals and an installed, signed-in Stable app. Changes to Warp, its authentication or the server can break it.
- The key is fixed to the physical backtick / `ё` key. Press-and-hold starts recording after a short threshold; starting to speak immediately can clip the beginning.
- Accuracy can differ from Warp's own voice input even though both request Wispr. Capture and resampling are different; exact server-side models and processing are not observable. See [docs/accuracy.md](docs/accuracy.md).
- Notifications can fail or be disabled. An empty transcript or network/authentication failure may not be obvious without the diagnostic log.
- No installer, auto-update, configurable hotkey, language selector, cancellation, or background launch setting yet.

## Troubleshooting

- **Nothing happens when holding the key:** check Accessibility and Input Monitoring; use **Проверить разрешения** or restart the app. Other hotkey tools and macOS Secure Input may intercept the key.
- **Recording starts but no text appears:** check the clipboard, the active app, and the diagnostic log. The app avoids pasting if it detects that the target changed.
- **Transcription fails:** verify that you're signed into Warp, Warp voice works, the internet is available, and Keychain access was granted. Warp may change or limit its internal API.
- **Accuracy differs from Warp:** wait until recording starts before speaking and compare both on the same microphone and phrasing. See the investigation notes below.

## Development and contributions

Issues and pull requests are welcome. Please describe your macOS and Warp versions, steps to reproduce, expected and actual behavior, and permission status. **Never include access tokens, Keychain data, personal audio or private transcripts in an issue.**

```sh
./build.sh
swiftc Sources/HoldKey.swift Tests/main.swift -o /tmp/warpvoice-key-test
/tmp/warpvoice-key-test
```

Useful contributions include configurable shortcuts and languages, reliable permission onboarding, better error reporting, recording quality comparisons, stable app signing, automated tests, and safer paste handling. Changes to authentication and audio handling should include clear privacy and security considerations.

Licensed under the [MIT License](LICENSE).

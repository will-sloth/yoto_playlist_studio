# Yoto Playlist Studio

A small native macOS app for creating and updating Make Your Own playlists, importing audio, and choosing 16×16 artwork. Requires macOS 13 or newer. The artwork editor uses native macOS frameworks. YouTube imports require the optional audio tools listed below.

## Try it

Open **Yoto Playlist Studio.app**, then choose **Explore demo playlist**. Select tracks, draw an icon or choose a starter design, and click **Use art**. Review the staged changes and apply them to the local demo. The demo editor does not contact Yoto; live community browsing and YouTube downloads contact their respective services when requested.

The editor supports a transparent eraser, a color palette, stroke undo, five starter designs, image import fitted to 16×16, and PNG export. The black preview approximates a player's display; actual LED colors may vary.

## Connect your first Yoto developer application

1. Sign in at [dashboard.yoto.dev](https://dashboard.yoto.dev/).
2. Create an application named **Yoto Playlist Studio**. Choose **Public Client** when prompted for the client type. This desktop app uses browser sign-in with PKCE, without a client secret.
3. Register the redirect/callback URL exactly as `http://127.0.0.1:8787/callback`.
4. Copy the application's **Client ID**.
5. In Playlist Studio, click **Connect to Yoto**, paste the Client ID, then click **Sign in with Yoto**.
6. Sign in in the browser and approve access to your Make Your Own content and icons. Return to Playlist Studio.

If the dashboard exposes permission settings, enable `user:content:manage`, `user:content:view`, `user:icons:manage`, and renewable sign-in (`offline_access` / refresh tokens). The app requests these scopes during sign-in. Dashboard field names can change; Yoto's [desktop authentication guide](https://yoto.dev/authentication/headless-cli-auth/) is the reference.

Your Client ID is remembered in preferences; access/refresh tokens and their expiry are stored in macOS Keychain, on this Mac only. Sign in once in version 0.14.0 or later to grant `offline_access`. The app reconnects on launch and renews expired sessions automatically, including while polling audio processing. Refresh tokens are single-use, so renewal is shared across parallel requests and every replacement is saved before use. Disconnect/Forget saved sign-in removes the saved credential; no password or client secret is stored. If Yoto revokes or expires the refresh token, sign in again. Temporary connection/server failures keep the saved session for retry. If no refresh token is issued, the app explains the public-client setup needed; the saved access token works only until it expires. Keychain errors are shown instead of falling back to plaintext files. Do not paste a client secret or your Yoto password into Playlist Studio. The local sign-in listener binds only to 127.0.0.1, closes after a valid callback, and times out after three minutes.

## Add artwork to a playlist

1. Choose an existing MYO playlist on the left.
2. Select one or more tracks.
3. Tracks without artwork get automatic icon suggestions with a preview and matching reason. Existing track or inherited chapter art is kept without automatic recommendations. Use **Suggest a different icon** on an individual track, or **Suggest icons for songs**, to explicitly request alternatives for tracks that already have artwork. Click **Accept** to stage it, or **Reject** to keep its current icon. **Reject** reveals a subject search plus **Try another match** and **Create new pixel art…**. Refine a subject such as “polar bear” and retry; previously rejected icons are skipped. **Suggest icons for songs** also offers alternatives after rejection and skips tracks with staged art. Matching uses song titles and public Yoto icon names/tags on your Mac; it does not listen to audio or use AI. Simple starter art is the fallback.
4. Use **Create art** to draw/import, or **Yoto library** to search Yoto's public icons by title or tag. Clicking a library icon stages it for selected tracks.
5. Click **Review changes** to see the affected tracks.
6. Click **Apply to Yoto** to upload custom art and update the existing playlist.

Audio URLs, track keys, ordering, metadata, and other content settings are retained. Editing a chapter's first track also changes the chapter-selection icon. Editing other tracks only changes those track icons. The app rejects a save if the playlist changed since it was loaded. There is still a small window for changes by another app between the final check and the write; avoid editing the same playlist simultaneously elsewhere.

A JSON snapshot is written before uploads in `~/Library/Application Support/YotoPixelStudio/Backups`. These files contain playlist metadata and audio references; keep them private. This version has no one-click restore. If an upload succeeds but the playlist update fails, the unused uploaded icon may remain in your Yoto account; your draft remains available to retry.

## Download YouTube audio and append it to an existing playlist

1. Connect to Yoto and choose an existing MYO playlist. Apply or discard any staged icon edits first.
2. Click **Add audio…** in the top bar.
3. Paste one or more HTTPS YouTube video URLs, one per line, then click **Download MP3s**. Duplicate video URLs are skipped, preserving the first occurrence. Video links with playlist parameters are reduced to the single video; whole-playlist import and live streams are not supported.
4. For each queued video, the app checks available formats and downloads the best available audio, encodes a stereo 44.1 kHz MP3 at 320 kbps, and verifies the encoded audio stream bitrate using ffprobe. Review each track title and use **Preview** beside it. Failed downloads remain in the queue; **Download / retry** retries those while keeping successful downloads. **Save MP3…** exports a local copy if you want to keep it.
5. Check the destination playlist shown at the top, then click **Upload N track(s)**. The count includes ready downloads only; failed ones are skipped. This is the final write action. The app uploads the MP3, waits for Yoto's audio processing, saves a JSON playlist backup, then appends the batch in queue order in one final playlist write. If one audio upload fails, no batch tracks are appended; retry reuses already processed media in this window.
6. Existing tracks and art remain in place. The new track appears with icon suggestions after saving.

Use videos you are allowed to download and copy. 320 kbps is the MP3 output encoding rate, not a promise of 320 kbps source quality: transcoding cannot recover information absent from YouTube's audio. Yoto processes the uploaded file and may use a different final codec or bitrate. The app does not import browser cookies, sign in to YouTube, or bypass DRM/access restrictions. Restricted videos may fail.

### One-time audio-tool setup

The app finds `yt-dlp`, `ffmpeg`, `ffprobe`, and `deno` in Homebrew's standard locations or the process PATH. They are not bundled, so the app stays small. With [Homebrew](https://brew.sh/) installed, run:

```sh
brew install yt-dlp ffmpeg deno
```

Then click **Check tools** in the audio window. If YouTube changes its download behavior later, update the tools with `brew upgrade yt-dlp ffmpeg deno`. [yt-dlp's official installation guide](https://github.com/yt-dlp/yt-dlp#installation) documents other installation options.

Downloads and conversions run as separate local processes without a shell, with configuration/plugin loading disabled. Every completed MP3 is copied to **~/Music/Yoto Playlist Studio** before it is marked ready. **Open local copies** opens that folder. Copies remain after uploading, closing, cancelling later queue items, or editing the link list. Repeat imports check saved MP3s for the same video and reuse a valid 320 kbps copy before contacting YouTube. New downloads get numbered filenames and never overwrite earlier copies. Closing the window only cancels work and removes temporary conversion files; permanent MP3 copies are retained. Upload cannot be dismissed interactively while in progress. A successfully uploaded media file may remain unused in Yoto if processing or playlist saving fails; the app does not automatically retry the final playlist write. If a network failure happens during that final save, check the Yoto playlist before trying again to avoid adding the same track twice. The app checks for playlist changes before and after upload, but the API still has a small race window between the final check and save.

Existing and new playlists are supported. Batch imports are supported; album splitting and automatic trimming are not. Demo mode disables upload. Final playlist saving and custom icon resolution still need live verification.

[Official Yoto audio upload workflow](https://yoto.dev/myo/uploading-to-cards/)

## Community icons inside the app (no OpenAI key)

Select one or more tracks, choose the **Community** artwork tab, then **Browse community icons…**. Or click **Search community icons…** under a rejected suggestion; that targets just the rejected track.

- **Yoto Icons:** enter a short subject such as “polar bear” and click **Search**. Click an icon, then its **Download** link.
- **Yoto Everything:** choose it in the Source menu. Use **Find on page**, or browse its categories. Use the **↓** image-download links.
- The chosen file appears in a native 16×16 preview. **Accept icon** stages it for the targeted tracks. Finish with **Review changes → Apply to Yoto**. Closing without accepting leaves artwork unchanged.
- If a website download does not work, use **Import downloaded file…** to select an icon you downloaded separately.

The sites are displayed live in an embedded WebKit browser with an isolated, nonpersistent website session. This is not a bulk-copy or undocumented API integration. Only the subject you search is sent to the site; the app does not hand over its Yoto token, playlist audio, or OpenAI key. External navigation is blocked in the community browser. The sites' own Yoto account-connection features are not part of this integration; use image downloads and Playlist Studio's final review.

PNG/JPEG/GIF icon downloads are decoded locally. GIFs become a still image in this version. Downloads use temporary files removed after import or browser close; files larger than 8 MB are rejected. Browsing requires internet and depends on the sites remaining available and keeping their download links compatible.

[Yoto Icons](https://www.yotoicons.com/) remains the source for its community art and creator information. [Yoto Everything's licence](https://www.yotoeverything.com/license) allows personal/family card use and editing; its library is not bundled or republished with this app.

## Generate original pixel art after rejection

Choose **Create new pixel art…** under a rejected song. Edit the subject description (Polar Bear titles are prefilled with a white bear face), then enter your own OpenAI API key in the secure field. Get a key from [OpenAI's API dashboard](https://platform.openai.com/api-keys). Do not send the key in chat.

Click **Generate** to send only the description and icon-style instructions to OpenAI's Images API (`gpt-image-2`, one image, low quality). API billing and model access are required independently of a ChatGPT subscription. The key is kept in this window's memory, never written to preferences or bundled in the app. Closing the window clears its key and cancels a pending request; a request already processed by OpenAI may still incur a charge.

The generated image is reduced locally to an exact 16×16 PNG on black. Inspect the pixel preview and choose **Generate another** or **Accept art**. Each generation is a separate API request. Accept only stages artwork for that track. Use **Review changes → Apply to Yoto** to save it. Accepted generated pixels are also loaded into the editor and that track is selected for further editing.

AI generation was tested with simulated API responses and image round trips. No paid live image-generation request was made during development; live access, subject quality, and billing must be validated with your own API key. The model may produce art that needs another generation or manual cleanup at this tiny resolution.

[Official Images API reference](https://developers.openai.com/api/reference/resources/images/methods/generate)

## Current scope

Implemented: native interface, browser authorization, MYO playlist listing, track selection, public Yoto icon search/reuse, pixel drawing and starter designs, per-song icon suggestions with accept/reject and per-track retries, optional AI generation with preview, embedded community-site browsing and download-to-preview, YouTube audio download/320 kbps MP3 encoding and append-to-playlist, import/export, reviewed updates, local backups, stale-content check, demo mode.

Not yet implemented: automatic backup restore and notarized distribution. The starter designs are generated locally from simple shapes, not by AI. Existing icon previews use playlist image URLs, inherited chapter artwork, and authenticated resolution of custom icon references. Artwork is preserved unless replaced.

Live account behavior still needs verification with your own developer client and a test MYO playlist.

## Build from source

Install Apple's Command Line Tools or Xcode. Double-click `build-app.command` to build, package, locally sign, and launch the app. Alternatively, open `Package.swift` in Xcode. The bundled app is built for the current Mac's CPU; rebuild for other architectures. Local signing is suitable for this prototype, not App Store distribution.

Run checks by double-clicking `verify.command` (works with Command Line Tools). With full Xcode installed, you can also run `swift test`. Checks cover preservation of audio and unknown content fields, rejected stale track selections, chapter/track icon behavior, and 16×16 PNG orientation/transparency round trips.

## API references

- [MYO playlists](https://yoto.dev/api/content/getusersmyocontent/)
- [Public icons](https://yoto.dev/api/icons/getpublicicons/)
- [Upload custom icons](https://yoto.dev/icons/uploading-icons/)
- [Update existing content](https://yoto.dev/api/content/createorupdatecontent/)

Yoto's icon-upload guide currently shows both multipart and binary examples. This prototype uses the documented raw PNG example with `Content-Type: image/png` and `autoConvert=false` because it already produces exact 16×16 images. Confirm this on a test playlist first.

Version 0.6.2: checks downloadable formats before selection; reuses verified archived MP3s; sends the source checksum as hexadecimal SHA-256; reports Yoto failure step and server reason. Live YouTube retest succeeded. Corrected Yoto upload still needs account verification.

Version 0.6.3: new chapter IDs fit Yoto’s 20-character limit and avoid existing chapter keys. Fixes playlist save rejection after successful audio processing. Build and regression checks passed; live playlist save awaits retry.

Version 0.6.4: existing song previews use playlist image URLs, including chapter inheritance, and resolve custom Yoto icon references through the authenticated media API. Public library matching remains a fallback. Track overrides never display an unrelated chapter image. Existing art still suppresses automatic suggestions. Release build and fixture checks passed; live account preview verification remains pending.

Version 0.7.0 renames the app to Yoto Playlist Studio. Existing client-ID preferences and backup storage are retained. New MP3s go to Music/Yoto Playlist Studio; repeat imports also search the earlier Music/Yoto Pixel Studio folder.

Custom icon previews now load your personal Yoto icon library (/media/displayIcons/user/me), with a Reload icons action and visible failure details. The new application icon is bundled for Finder and the Dock. Live custom-icon verification remains pending.

## Create a new playlist

Connect to Yoto and choose **New playlist…** in the sidebar. Enter a name and click **Start playlist**. This starts an unsaved local draft, marked **(new)**. Add audio using **Add audio…** or **Public-domain audio…**. After preparing and reviewing the tracks, click **Upload N track(s)**. The app creates the playlist with its first batch of audio in one final save. No empty placeholder is created on Yoto. Unsaved drafts last only for the current app session; closing an audio window keeps completed MP3 files locally. **Refresh** reloads saved playlists without discarding local playlist drafts.

Creation uses Yoto's documented POST /content flow without a cardId; existing playlists still use their own IDs. If the final creation request fails or returns no ID, refresh your library before starting again to check whether the request succeeded. The window prevents an immediate repeat creation request after an uncertain result.

## Public-domain audio

Select an existing playlist or start a new one, then choose **Public-domain audio…**. Browse [Yoto Space's public-domain catalog](https://yoto.space/public-domain). Click a book's **Add to your library** link to load its public share page into a native track-selection screen; this action previews tracks in Playlist Studio rather than immediately adding a card to your account. Alternatively, paste a `https://share.yoto.co/s/…` link and click **Load tracks**.

Select the chapters you want (or choose **All**) and click **Prepare selected track(s)…**. In the audio window, click **Download MP3s**, review the titles and previews, then **Upload N track(s)**. Tracks follow the collection's order. Available source artwork is downloaded, fitted to 16×16, and uploaded along with each selected track. Artwork download failures are shown while leaving the audio usable. Tracks with copied artwork do not receive automatic icon suggestions.

For other sources, use **Add audio… → Public audio files** and paste direct MP3, M4A, AAC, Ogg, Opus, WAV, FLAC, or AIFF file links, one per line. Public audio imports require only FFmpeg and ffprobe; yt-dlp and Deno are needed only for YouTube. Public audio is encoded as stereo 44.1 kHz, 320 kbps MP3; this does not improve source quality. Files remain in **~/Music/Yoto Playlist Studio** after upload or closing. Repeat imports reuse valid local copies, including when Yoto's temporary download signatures have changed.

The embedded catalog has an isolated, nonpersistent browser session. App Yoto credentials are never forwarded to the catalog or media download hosts. The app reads publicly delivered share-page data and imports only the tracks you choose; it does not scrape the catalog in bulk or use a hidden sharing API. Only HTTPS source/redirect URLs are accepted, with local hostnames and literal IP addresses excluded. Individual source files are limited to 512 MB after download; images and share pages to 8 MB. Share links can expire or change format. Refresh/reopen the shared collection if a temporary media URL expires. Sources with no public downloadable audio are rejected. Direct audio links must point to files, not ZIP archives or article pages.

Version 0.8.0: public-domain browser and chapter selection, direct audio links, original artwork copying, permanent MP3 copies and reuse, new playlist drafts and creation with the first audio upload, library refresh, and API contract checks. A real public-domain chapter from *A Child's Garden of Verses* was downloaded with artwork and verified as a 320,000 bps MP3 (516.02 seconds); repeat import reused the retained local file. Final live Yoto upload/creation still requires account verification. No new playlist was written to a live account during these checks.

## Parallel downloads and uploads

The audio window has a **Simultaneous tracks** setting: **1**, **2**, or **3**, defaulting to **3**. This applies to YouTube/public audio downloads and conversion, and to Yoto artwork/audio uploads and processing. Each active download uses its own downloader instance and temporary directory; each queue row displays its own progress. Completed tracks remain in their original queue positions, regardless of completion order.

Download failures do not stop other tracks; Download / retry keeps successful MP3s and retries missing ones. Upload failures let other in-flight tracks finish processing but prevent the final playlist save. Retrying Upload reuses already uploaded artwork and processed audio in the same window. The playlist itself is saved once, after all ready tracks have processed successfully. Cancelling downloads stops active download/conversion work and prevents queued tasks from starting; permanent MP3 copies remain. Choose **1** for sequential work if a source is rate-limiting or you prefer lower resource use. Speed depends on connection, conversion time and Yoto processing.

Version 0.9.0: bounded parallel downloads/conversion and uploads/processing, selectable concurrency, independent row progress and cancellation, successful-work reuse after failures, stable playlist ordering, and separate processing diagnostics for each upload. Concurrency, order, cancellation and partial-failure behavior passed automated checks. The real upload service was exercised concurrently with simulated upload/poll responses; no live account was changed for these tests.

Version 0.9.1: YouTube HTTP 403 errors trigger one fresh extraction after a short pause, discarding only temporary partial download files. Cancellation and permanent MP3 copies are preserved. A second failure suggests trying later or a direct audio link.

Version 0.9.2: batch upload failures include track titles and underlying reasons; audio-processing errors in HTTP 202 responses are surfaced immediately, and signed-upload failures include their HTTP status. Permanent MP3s and successful batch results remain available.

Version 0.9.3: before any upload, recordings longer than two hours prompt for Trim and upload or Abort. Trimming keeps the first 1:59:59 in a separate verified 320 kbps MP3, preserves the full original and artwork, and leaves the playlist unchanged on abort or trimming failure.

Version 0.10.0: select one or more tracks, then choose **Move selected tracks to playlist…** and an existing destination. Audio references, titles, artwork and playback settings move together without downloading or re-uploading the audio. Tracks append in their original order. Apply or discard staged artwork first. Both playlists are backed up before writing; the app confirms the destination copy before removing originals and refuses stale edits. If a move fails, **Resume track move…** checks both playlists and finishes without duplicating copied tracks. Closing the move sheet retains its retry state until the app quits or disconnects; **Stop moving** leaves any saved copies in place. Moves are checked with simulated Yoto responses, including failed saves and lost responses; live account moves still need verification.

Version 0.11.0: **Add audio… → Local MP3s → Choose MP3 files…** accepts one or several local files, skips duplicate selections, and prepares them in the existing batch queue. Preview, edit titles, then upload. Valid MP3s retain their original bytes and bitrate; a permanent copy is saved in Music/Yoto Playlist Studio, and originals are never changed. Titles use the embedded title when available, otherwise the filename. Local import needs ffprobe (installed with FFmpeg), but no YouTube tools or network. The two-hour trim prompt also supports local MP3s at their original bitrate.

Version 0.12.0: the link source now accepts public SoundCloud track links as well as YouTube, including mixed batches. Use full soundcloud.com/artist/track URLs (profiles, sets, private links and short share URLs are not supported). Downloads use the best stream available to yt-dlp, are encoded as 320 kbps MP3s and kept locally; encoding cannot improve the source quality. SoundCloud-only batches do not require Deno. Tracking parameters are removed and cache IDs stay separate from YouTube downloads.

Version 0.12.1: consecutive audio batches no longer reject a playlist merely because its timestamp or an earlier snapshot changed. Each existing-playlist append fetches and backs up current server content immediately before saving, preserves intervening tracks/artwork/settings, and adds the new tracks at the end. Retrying failed processing still reuses successful track results. Other destructive editing operations retain their conflict checks.

Version 0.13.0: choose **Reorder tracks…** to drag songs into order or use up/down arrows. Changes stay local until **Save order**; Cancel discards them and Reset restores the starting order. Audio references, artwork, chapter settings and unrelated playlist fields are retained. Chapter groups split only when needed to support the new song order. Numeric default track labels follow the new order; custom labels remain. Saving fetches the current playlist, tolerates timestamp-only changes and preserves current title/metadata, backs up before writing, and refuses changed tracks/artwork. Reload latest order resolves a conflict without restarting. Reordering is also available in the local demo.

Version 0.14.0: persistent Yoto sign-in in macOS Keychain, automatic restore/renewal and one HTTP-401 retry, rotating refresh-token handling with parallel-request coalescing, and safe sign-out. Session tests use injected storage and simulated auth/API responses, including revocation, temporary errors, missing rotation, persistence failure and logout during renewal. No real credentials or Keychain entries were used during automated verification; a real sign-in is still required to enable and verify renewal for your public client.

### Check duplicates within a playlist
Choose a playlist, then **Check duplicates…**. The read-only report fetches the latest playlist and groups repeated Yoto audio references (even under different titles). Matching titles with different or unknown audio are shown separately as possible matches. Each entry includes its current track number. Signed links on Yoto's media host are normalized for comparison. Files are not downloaded or compared by sound; differently encoded copies with different titles may not be detected. The checker never removes tracks or changes the playlist. **Check again** refreshes the report.

Version 0.14.1: **Stay signed in on this Mac** is optional. If Yoto shows its generic error before the login form, cancel the pending attempt, verify your Client ID/public-client/callback settings, and retry with the switch off to use the earlier session-only scopes. Session-only login does not save tokens and removes an older saved sign-in after successful login. A visible **Cancel sign-in** button stops pending browser sign-in, and cancelled attempts cannot save a late token response. This fallback does not prove or repair a server-side/client-dashboard misconfiguration.

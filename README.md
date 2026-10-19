# Yoto Playlist Studio

A small native macOS app for adding 16×16 artwork to existing Make Your Own playlists. Requires macOS 13 or newer. The artwork editor uses native macOS frameworks. YouTube imports require the optional audio tools listed below.

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

If the dashboard exposes permission settings, enable `user:content:manage`, `user:content:view`, and `user:icons:manage`. The app requests these scopes during sign-in. Dashboard field names can change; Yoto's [desktop authentication guide](https://yoto.dev/authentication/headless-cli-auth/) is the reference.

Only your Client ID is remembered. Access tokens stay in memory and are discarded on quit or disconnect. Sign in again if your session expires. Do not paste a client secret or your Yoto password into Playlist Studio. The local sign-in listener binds only to 127.0.0.1, closes after a valid callback, and times out after three minutes.

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
2. Click **Add YouTube audio…** in the top bar.
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

Only existing playlists are supported. Batch imports are supported; album splitting, automatic trimming, and playlist creation are not. Demo mode disables upload. Final playlist saving and custom icon resolution still need live verification.

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

Not yet implemented: persistent login/refresh tokens, automatic backup restore, notarized distribution. The starter designs are generated locally from simple shapes, not by AI. Existing icon previews use playlist image URLs, inherited chapter artwork, and authenticated resolution of custom icon references. Artwork is preserved unless replaced.

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

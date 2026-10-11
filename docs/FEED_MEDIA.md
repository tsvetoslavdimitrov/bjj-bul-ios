# Feed media: photos, video, music links

Migration: `supabase/migrations/0010_feed_media.sql` (also `/workspace/bjj-bul-0010.sql`).

## Photos & video
- Composer: in-app camera (`UIImagePickerController`, photo or video, max 60 s, `.typeMedium`), PhotosPicker for photos,
  and a separate PhotosPicker for one library video. Up to 4 items, at most 1 video.
- Images: JPEG via `ImageCompressor` (1600 px, q 0.7). Videos: re-encoded with `AVAssetExportSession`
  (`AVAssetExportPresetMediumQuality`, MP4, network-optimised). Videos over 60 s or over 50 MB after export are rejected.
- Storage: `post-media/<uid>/<post id>/<n>.jpg|.mp4`. Bucket limit 50 MB; allowed `image/jpeg|png|heic`, `video/mp4|quicktime`.
- `post_media.kind` = `image | video`. The app also detects video by file extension, so older rows work.
- Playback: `VideoPlayer` (AVKit) starts **muted** when the card appears and pauses when it disappears. The speaker button turns on sound.
- Cost: video storage and egress add up quickly on Supabase (1 GB storage / 5 GB egress on the free tier). Consider lowering to
  `AVAssetExportPreset960x540` or moving video to a CDN / Mux / Cloudflare Stream later.

## Music (song links only)
- Users paste a Spotify / Apple Music / YouTube Music / Deezer link. The app fetches metadata on the device:
  - Spotify: `https://open.spotify.com/oembed?url=<link>` (title + artwork)
  - YouTube Music: `https://www.youtube.com/oembed?url=<link with www.youtube.com>&format=json`
  - Deezer: `https://api.deezer.com/oembed?url=<link>&format=json`
  - Apple Music, or any fallback: Open Graph tags (`og:title`, `og:description`, `og:image`) from the page
- Stored on `posts.music_url / music_title / music_artist / music_artwork` (a DB check limits hosts to these providers and requires https).
- The card opens the link. iOS hands universal links to the Spotify / Music / YouTube Music / Deezer app when it's installed.
- **No audio is mixed into videos and no audio is hosted.** Putting commercial music into user videos needs sync licences that we don't have.

## Future: MusicKit (Apple Music)
- MusicKit (iOS 15+) can search the Apple Music catalog and show previews/artwork without scraping:
  `MusicCatalogSearchRequest`, `Song.previewAssets`, `ApplicationMusicPlayer` for subscribers.
- Needs: the MusicKit App Service enabled for the App ID in the developer portal, `NSAppleMusicUsageDescription`,
  and `MusicAuthorization.request()`. Catalog search doesn't need a user subscription; full playback does.
- Possible features: a song search picker in the composer (instead of pasting links) and 30-second previews in post cards.
  Still no mixing into uploaded videos (licensing).
- Spotify's equivalent (iOS SDK / Web API search) needs an app registration and the user's Spotify login; it's not planned.

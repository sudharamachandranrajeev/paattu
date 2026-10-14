# just_audio_media_kit (Paattu's copy)

[just_audio_media_kit](https://github.com/Pato05/just_audio_media_kit) 2.1.0,
public domain (see LICENSE), with two additions for Paattu's equaliser on
Windows and Linux:

- `JustAudioMediaKit.setAudioFilters(af)` sets mpv's `af` (audio filters) on
  every player, and on players made later (`JustAudioMediaKit.audioFilters`).
- `JustAudioMediaKit.command(args)` sends an mpv command to every player, for
  `af-command` (moving a filter while it plays).

Set `JustAudioMediaKit.pitch = false` with these: with pitch control on,
media_kit overwrites `af` with `scaletempo` whenever the speed changes.

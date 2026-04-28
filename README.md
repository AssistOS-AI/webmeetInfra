# webmeetInfra

Ploinky repository for WebMeet runtime infrastructure services.

Agents in this repo provide the media stack used by `AchillesIDE/webmeetAgent`:

- `webmeetInfra/stack` dependency bundle
- `webmeetInfra/webmeetRedis`
- `webmeetInfra/webmeetCoturn`
- `webmeetInfra/webmeetLivekitServer`
- `webmeetInfra/webmeetLivekitEgress`

The app-facing WebMeet agent remains in `AchillesIDE`; this repository only owns reusable runtime services.

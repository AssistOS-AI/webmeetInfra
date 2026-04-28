# stack

Infrastructure dependency bundle for `webmeetAgent`.

It brings up the full WebMeet media stack as agent dependencies:

- `webmeetInfra/webmeetRedis`
- `webmeetInfra/webmeetCoturn`
- `webmeetInfra/webmeetLivekitServer`
- `webmeetInfra/webmeetLivekitEgress`

## Usage

Do not start this bundle manually from the CLI for normal WebMeet usage.

Enable `webmeetAgent` and let Ploinky resolve `webmeetInfra/stack` as a dependency of that agent.
This keeps LiveKit startup inside the agent dependency graph for both `dev` and `prod` profiles.

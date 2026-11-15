@AGENTS.md

## After a change merges to `main` (sraja7272/sure fork)

The live install runs this fork's image through Komodo, pinned by tag and digest in `Raja-Server/finance/compose.yaml` of `sraja7272/Docker-Stacks`. A merge is not deployed until that file is updated, so every time a change merges to `main`:

1. Watch the `Publish Docker image` workflow run for the merge commit until it finishes. If it fails, stop and report the failing step.
2. Once it succeeds, confirm the tag `ghcr.io/sraja7272/sure:sha-<full merge commit SHA>` exists and read its multi-arch index digest from the registry.
3. Open a pull request on `sraja7272/Docker-Stacks` that changes only the `web` and `worker` image lines in `Raja-Server/finance/compose.yaml` to `ghcr.io/sraja7272/sure:sha-<SHA>@sha256:<digest>`. Branch from the latest `origin/main` and leave untracked files in that checkout alone.
4. In the PR description, say which change the image carries, whether it adds database migrations (they run one way on first boot, so a database backup comes first), and that it has not been deployed or tested on the server.
5. Do not merge that PR; merging it is what deploys.

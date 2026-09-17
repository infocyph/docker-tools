# docker-tools — Hardening, Control-Plane & AI Consumer Plan

## Status

Planning branch: `plan/docker-tools-hardening-ai`

Baseline:

- Repository: `infocyph/docker-tools`
- Default branch: `main`
- Current published release: `0.21.1`
- Current runtime base: `alpine:latest`
- Runtime role: LocalDevStack control-plane / developer toolbox / admin panel / runtime-template generator
- Completed lower layers: shared Scriptomatic/Toolset foundations, `runner:0.5`, `nginx:0.4.1`
- Apache hardening is handled separately in `docker-apache`; this plan does not move Apache responsibilities into Tools.
- Local LLM runtime is provided separately by `infocyph/docker-llm-sm`.

This plan supersedes the older LocalDevStack ecosystem-only Tools draft and incorporates lessons from the previously reverted `feature/ai` experiment.

---

# 1. Goal

Harden `docker-tools` as the LocalDevStack control plane while making it the primary **AI consumer** in the ecosystem.

Tools should remain fully functional without AI. When `docker-llm-sm` is available, Tools should be able to use it through a small, reusable provider layer for many future developer/ops workflows.

The core architectural rule is:

```text
LocalDevStack / docker-tools = AI consumer

docker-llm-sm = AI runtime/provider
```

Never embed or start Ollama inside `docker-tools` again.

---

# 2. Lessons from the reverted AI experiment

The old `feature/ai` branch embedded Ollama directly into the Tools image, exposed port `11434`, started/stopped an Ollama daemon in the Tools entrypoint, pulled models there, and made `askai` target loopback.

That approach was correctly reverted.

The new architecture must explicitly avoid:

- installing Ollama in `docker-tools`;
- exposing `11434` from Tools;
- model downloads/storage in Tools;
- Ollama process supervision in the Tools entrypoint;
- coupling Tools startup to model availability;
- duplicating `docker-llm-sm` CLI/model lifecycle logic.

Tools only needs HTTP/API access to the provider.

---

# 3. Architecture invariants

Preserve these responsibilities:

- `server-tools` remains the LocalDevStack control-plane container.
- Tools owns local-domain/vhost generation, TLS helper workflows, environment/SOPS helpers, runtime/profile selection, monitors, admin panel, and developer utilities.
- PHP/Node runtime image generation remains driven by Tools templates but built by LocalDevStack.
- Docker socket access remains an explicit LocalDevStack integration choice and must be audited/minimized.
- Toolset remains a reusable external CLI dependency rather than copied raw from `main`.
- Scriptomatic remains an external shared bootstrap/helper source.
- AI must be optional and failure-isolated.
- Docker DNS/service names replace static-IP assumptions.
- User/project content must never be sent to an external model provider implicitly.
- Local `llm-sm` should be the preferred provider when present.

---

# 4. Shared dependency contracts

## 4.1 Scriptomatic

Move all stale `Scriptomatic/master` references to the completed canonical contract:

```text
https://raw.githubusercontent.com/infocyph/Scriptomatic/main/...
```

Use bounded downloads, syntax checks and explicit failure handling.

Where reproducibility materially matters, support a full-SHA build argument, but do not invent a Scriptomatic release/tag dependency.

## 4.2 Toolset

Stop raw `Toolset/main/...` downloads.

Install required Toolset commands through the stable checksum-verifying release installer:

```text
https://github.com/infocyph/Toolset/releases/latest/download/install.sh
```

Current Tools image consumers include at least:

- `gitx`;
- `chromacat`;
- `sqlitex`;
- `netx`.

Install only the commands actually used.

Verify installer syntax and each installed command's `--version` contract.

The image should naturally inherit Toolset's existing Ollama-aware `gitx` support by pointing `GITX_OLLAMA_URL` at the LocalDevStack LLM service.

---

# 5. AI provider architecture

## 5.1 Provider contract

Introduce a small Tools-side provider configuration, not another model runtime.

Recommended environment contract:

```text
LDS_AI_ENABLED=auto
LDS_AI_PROVIDER=ollama
LDS_AI_URL=http://llm-sm:11434
LDS_AI_MODEL=
LDS_AI_TIMEOUT=600
```

Semantics:

- `LDS_AI_ENABLED=auto`: use AI only when provider is reachable.
- `LDS_AI_ENABLED=0`: never attempt AI.
- `LDS_AI_ENABLED=1`: AI-capable commands may fail clearly if provider is unavailable.
- `LDS_AI_PROVIDER=ollama`: initial provider implementation.
- `LDS_AI_URL`: defaults to Docker DNS name `http://llm-sm:11434` inside LocalDevStack.
- `LDS_AI_MODEL`: optional model override; if empty, provider/runtime default applies.
- no API key is required for the local Ollama path.

Do not use `https://llm.localhost` for container-to-container calls. Inside Docker, Tools should call `llm-sm:11434` directly. `https://llm.localhost` is the user-facing Nginx route.

## 5.2 Provider library

Add a small reusable shell library, for example:

```text
scripts/lib/ai-provider.sh
```

Responsibilities:

- normalize AI configuration;
- provider reachability check;
- discover installed/default model when needed;
- submit prompt requests;
- submit structured JSON requests;
- support streaming and non-streaming modes;
- apply timeouts and bounded retries;
- return useful provider errors;
- never start/pull/remove models;
- never own persistence.

Keep the initial implementation Ollama-focused but design function boundaries so additional providers can be added later without rewriting every AI consumer.

Suggested shell functions:

```text
ai_available
ai_model
ai_generate
ai_generate_json
ai_stream
```

Avoid a heavyweight framework.

---

# 6. AI usage surface in docker-tools

The plan should enable several future uses without implementing every idea in one release.

## Phase A — foundation + immediately useful commands

### `askai`

Add/reintroduce `scripts/shells/askai.sh` as a pure client.

Support:

- prompt argument;
- file input;
- stdin input;
- optional instruction/system text;
- optional model override;
- optional JSON mode;
- context-size/timeout guards;
- provider-unavailable error that does not affect other Tools functions.

Unlike the reverted branch, `askai` must use `LDS_AI_URL` / provider library rather than fixed loopback `127.0.0.1:11434`.

### `gitx` integration

Configure Toolset `gitx` to use:

```text
GITX_OLLAMA_URL=http://llm-sm:11434
```

when LocalDevStack AI is enabled.

Do not duplicate `gitx ai-commit` logic in Tools.

## Phase B — operational intelligence

Design reusable commands/actions around existing monitors:

- explain current stack status;
- summarize Docker/service logs;
- summarize monitor alerts;
- explain SLO failures;
- explain database-health anomalies;
- explain queue-health anomalies;
- explain TLS failures;
- explain volume/disk pressure;
- summarize drift-monitor differences;
- suggest troubleshooting steps from collected diagnostics.

Important: deterministic monitor collection remains non-AI. AI receives a bounded, sanitized snapshot after the normal monitor has collected facts.

## Phase C — developer assistance

Potential future capabilities:

- project/repository review;
- staged diff / commit assistance through `gitx`;
- generated local environment explanations;
- PHP/Node runtime configuration suggestions;
- Composer/npm failure explanation;
- Docker/Compose error explanation;
- Nginx/Apache vhost explanation;
- migration/config snippets;
- code-review summaries;
- Graphify output summarization/analysis;
- API/schema/documentation assistance.

These should reuse the same provider library instead of creating per-command curl implementations.

## Phase D — admin-panel copilot surfaces

Potential optional admin UI actions:

- "Explain this error" on logs;
- "Summarize last N minutes";
- "Explain unhealthy services";
- "Suggest fixes" for TLS/DB/queue/volume/drift panels;
- lightweight local chat over current LocalDevStack diagnostics.

Rules:

- never auto-execute destructive commands from model output;
- show exact diagnostic context being sent;
- keep action buttons opt-in;
- no hidden background AI calls;
- sanitize secrets/tokens/credentials before prompts.

---

# 7. Security and trust-boundary rules for AI

AI integration must explicitly protect LocalDevStack data.

Requirements:

1. Local provider by default.
2. No external provider fallback unless separately designed and explicitly enabled in the future.
3. Redact known credential values before sending diagnostics.
4. Do not include `.env`, SOPS decrypted content, SSH keys, Git credentials or tokens automatically.
5. Bound file/log input size.
6. Clearly distinguish model suggestions from deterministic health facts.
7. Never execute generated shell/SQL/code automatically.
8. If future actions are introduced, require explicit user confirmation and validate against allowlisted operations.
9. No Docker socket command should be generated and executed directly from LLM text.
10. CI tests use fake/mock Ollama endpoints; never require a real model download.

---

# 8. File-by-file hardening plan

## 8.1 `Dockerfile`

Plan:

- keep `alpine:latest` rolling policy;
- preserve multi-stage fetching where useful;
- modernize Scriptomatic/Toolset consumption;
- remove duplicate package declarations such as repeated `ripgrep`;
- inventory all installed packages against real command usage;
- keep PHP CLI because admin panel and helper scripts require it;
- preserve Docker CLI/Compose while Docker socket requirement is audited at LocalDevStack layer;
- harden mkcert/lazydocker/composer retrieval and verification;
- never install Ollama here;
- never expose `11434` here;
- copy new `scripts/lib/ai-provider.sh` and `askai` client only;
- run static/smoke validation during CI rather than bloating image build with test-only dependencies;
- preserve `notifierd` as main command unless later control-plane refactor proves otherwise.

## 8.2 `scripts/shells/entrypoint.sh`

Plan:

- keep certification, PHP-dir initialization and Git-default initialization best-effort where appropriate;
- preserve admin-panel autostart;
- do not start/supervise Ollama;
- initialize only AI environment aliases/defaults, not AI processes;
- validate optional `LDS_AI_*` values cheaply;
- preserve clean `exec "$@"` semantics when possible;
- add signal/child handling only for actual Tools-owned background services.

## 8.3 `scripts/shells/mkhost.sh` / `rmhost.sh`

- preserve domain/vhost creation/deletion behavior;
- remove static-IP assumptions where present;
- validate Docker DNS/service-name targets;
- align generated Nginx output with Nginx 0.4.1;
- align Apache output with the next hardened Apache release;
- add generated-config fixtures and syntax gates.

## 8.4 `scripts/http-templates/`

- inventory every Nginx/Apache/Node/PHP template;
- ensure Docker DNS names are used;
- align streaming/WebSocket behavior with Nginx 0.4.1;
- no LLM-specific Nginx routing belongs here if Nginx owns reserved `llm.localhost`; avoid duplicate route sources.

## 8.5 `scripts/docker-templates/`

- preserve PHP/Node runtime generation;
- remove duplicate service-version/profile truth where possible;
- consume canonical service/runtime metadata;
- keep PHP/Node as locally-built developer runtimes, not published generic images;
- prepare optional environment injection for AI-aware developer tools without adding `llm-sm` lifecycle here.

## 8.6 `scripts/fpm-templates/`

- verify generated PHP-FPM pool configs against current supported PHP versions;
- validate socket/TCP contracts used by Nginx and Apache;
- add syntax/fixture tests.

## 8.7 `scripts/shells/profile-chooser.sh`

- reduce duplication with LocalDevStack's service/profile definitions;
- move toward a canonical service catalog supplied by LocalDevStack;
- keep interactive UX but separate data from rendering/selection logic;
- add AI as an optional service/profile only when LocalDevStack integration phase defines its Compose contract.

## 8.8 Runtime version generation

Current Dockerfile downloads PHP/Node lifecycle data from endoflife.date during build.

Plan:

- keep fresh runtime metadata capability;
- validate API response shape before generating JSON;
- fail clearly or use a deliberate fallback when upstream is unavailable;
- add schema/fixture tests so upstream API changes do not silently produce broken profile data;
- record source timestamp/version in publish summary.

## 8.9 `scripts/shells/certify.sh`

- harden filesystem/permission handling;
- preserve existing LocalDevStack CA paths;
- keep certificate issuance responsibility in Tools, not Nginx/Apache;
- add idempotency tests.

## 8.10 `scripts/shells/env-store.sh` / SOPS paths

- audit secret boundaries carefully;
- never pass decrypted secret content to AI helpers;
- keep permissions restrictive;
- add tests for malformed paths, traversal and accidental stdout leakage.

## 8.11 Monitoring scripts

Existing monitors include runtime, TLS, DB, volumes, queue, SLO, log heatmap, drift and alerts.

Plan:

- preserve deterministic text/JSON output;
- standardize machine-readable mode where missing;
- make each monitor's JSON suitable as bounded input to future AI explanation commands;
- add timeouts around external/Docker/network probes;
- avoid command-string interpolation and unsafe eval patterns;
- AI explanation layers consume monitor output rather than modifying monitor truth.

## 8.12 Admin panel

Keep the admin panel deterministic first.

Plan:

- refactor repeated Docker/monitor invocation helpers where useful;
- validate/sanitize user-controlled request parameters;
- audit all shell-command construction;
- introduce an internal API/helper layer for AI later rather than embedding curl logic in each PHP page;
- add optional AI status indicator when `llm-sm` is reachable;
- future AI actions remain explicitly user-triggered.

## 8.13 `README.md`

Update after implementation stabilizes:

- define Tools as LocalDevStack control plane;
- document shared foundations;
- document AI as optional consumer functionality;
- document `llm-sm` as separate provider;
- document `LDS_AI_*` variables;
- document Docker socket security boundary;
- document admin panel and major command surfaces;
- document immutable release tags and `latest` refresh behavior.

---

# 9. CI plan

Add `.github/workflows/check.yml` with layers:

1. static shell validation and ShellCheck;
2. PHP syntax validation for admin panel;
3. generated template/config fixture validation;
4. unit/smoke tests for helpers;
5. real Docker image build;
6. container startup/admin-panel/notifier smoke;
7. Docker-socket integration tests only in disposable CI Docker environment;
8. fake Ollama HTTP server tests for `ai-provider.sh`/`askai`;
9. LocalDevStack compatibility checks;
10. architecture/release-contract audit preventing embedded Ollama from returning.

Permanent guards should fail if:

- `ollama serve` appears in Tools runtime scripts;
- Ollama binaries are downloaded into Tools;
- port `11434` is exposed by Tools;
- raw `Toolset/main` dependencies reappear;
- `Scriptomatic/master` reappears.

---

# 10. Publication workflow

Modernize `.github/workflows/docker.publish.yml` to the ecosystem contract:

- current Action majors;
- release event -> immutable version + `latest`;
- scheduled/manual refresh -> `latest` only from latest published source;
- immutable-tag existence guard;
- fresh amd64/arm64 candidate build and smoke gates;
- Docker Hub + GHCR multi-arch publish;
- BuildKit provenance and SBOM;
- GitHub attestations;
- post-publish digest/runtime verification;
- LocalDevStack compatibility gate before publish.

Because `alpine:latest`, runtime metadata, mkcert/lazydocker and latest Toolset are rolling inputs, publish summaries should record resolved versions/checksums wherever practical.

---

# 11. LocalDevStack integration contract

Tools should expect LocalDevStack to eventually supply:

```text
LDS_AI_ENABLED=auto
LDS_AI_PROVIDER=ollama
LDS_AI_URL=http://llm-sm:11434
```

and network connectivity to the optional `llm-sm` service.

User-facing browser/API access remains:

```text
https://llm.localhost
```

through Nginx 0.4.1+.

Tools does not create/start/remove the `llm-sm` container itself.

---

# 12. Acceptance criteria

The Tools hardening release is ready when:

1. permanent CI is green;
2. image builds from fresh rolling dependencies;
3. Scriptomatic/Toolset contracts match completed foundations;
4. no Ollama runtime exists inside Tools;
5. all existing Tools workflows remain functional without `llm-sm`;
6. `askai`/AI-provider tests pass against a fake Ollama endpoint;
7. `gitx` can use `llm-sm` through `GITX_OLLAMA_URL` when enabled;
8. monitors remain deterministic and machine-readable;
9. admin panel remains functional without AI;
10. generated PHP/Node/Nginx/Apache configs pass representative syntax tests;
11. release tags are immutable and scheduled refresh updates only `latest`;
12. Docker Hub/GHCR multi-arch publication, SBOM and provenance pass;
13. LocalDevStack compatibility gate passes with Runner 0.5, Nginx 0.4.1 and the hardened Apache release.

---

# 13. Recommended implementation batches

## Batch 1 — distribution/CI foundation

- permanent CI;
- shared dependency modernization;
- package/download audit;
- publish workflow modernization.

## Batch 2 — control-plane hardening

- entrypoint;
- host/domain generation;
- runtime/profile data;
- templates;
- SOPS/env boundaries;
- monitors;
- admin panel command safety.

## Batch 3 — AI consumer foundation

- `ai-provider.sh`;
- pure-client `askai`;
- `gitx` endpoint integration;
- fake-provider tests;
- AI security/redaction contract.

## Batch 4 — optional intelligence features

Add only after the provider layer is stable:

- log/alert explanations;
- health summaries;
- troubleshooting assistant;
- repository/config review helpers;
- Graphify-assisted analysis;
- admin-panel AI actions.

Each feature should remain small and reuse the same provider library.

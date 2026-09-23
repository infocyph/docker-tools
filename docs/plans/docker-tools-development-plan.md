# docker-tools — Consolidated Development, Hardening, AI & Document Intelligence Plan

## Status

Canonical plan: `docs/plans/docker-tools-development-plan.md`

Planning branch: `plan/document-structural-extraction`

Baseline:

- Repository: `infocyph/docker-tools`
- Default branch: `main`
- Runtime role: LocalDevStack control-plane / developer toolbox / admin panel / AI consumer
- LLM runtime remains external and is selected by `LDS_AI_RUNTIME`
- `LDS_AI_RUNTIME=npu` -> FastFlow at `http://llm-fastflow:11434/v1`
- `LDS_AI_RUNTIME=cpu|nvidia|amd` -> Ollama at `http://llm-ollama:11434/v1`
- LLM images remain inference-only
- This file supersedes the previous hardening/AI, provider-abstraction, and document-structural-extraction plan files.

---

# 1. Goal

Harden `docker-tools` as the LocalDevStack control plane while making it the primary **AI consumer** in the ecosystem.

Tools should remain fully functional without AI. When LocalDevStack AI is enabled, Tools resolves the active provider directly from `LDS_AI_RUNTIME` and uses that provider container through the shared OpenAI-compatible contract.

The core architectural rule is:

```text
LocalDevStack / docker-tools = AI consumer

docker-llm-fastflow / docker-llm-ollama = AI runtime/provider
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
- duplicating `docker-llm-ollama` CLI/model lifecycle logic.

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
- The selected LLM provider service identity is the only provider-neutral Tools target.

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

## 5.1 Provider-neutral contract

docker-tools is an AI **consumer**, never an LLM runtime.

LocalDevStack exposes the selected runtime to Tools through `LDS_AI_RUNTIME`. Tools
uses that value as the source of truth for the direct Docker-network target:

```text
npu             -> http://llm-fastflow:11434/v1
cpu|nvidia|amd  -> http://llm-ollama:11434/v1
```

FastFlow's standalone image defaults to port 52625, but LocalDevStack deliberately sets
`FLM_SERVE_PORT=11434`, so both provider containers expose the same internal API port
inside the LocalDevStack topology.

Recommended environment contract:

```text
LDS_AI_ENABLED=auto
LDS_AI_RUNTIME=<npu|cpu|nvidia|amd>
LDS_AI_MODEL=
LDS_AI_THINK=
```

The shared client uses only the OpenAI-compatible surface:

- `GET /v1/models`;
- `POST /v1/chat/completions`;
- OpenAI SSE streaming with `data: ...` and `data: [DONE]`.

Do not use Ollama-native `/api/tags`, `/api/generate`, or `/api/chat` from the shared
Tools client.

Do not route Tools-to-LLM traffic through `llm.localhost`. That hostname is for
user-facing/browser access through Nginx. Container-to-container traffic resolves the
active provider from `LDS_AI_RUNTIME` and talks directly to `llm-fastflow:11434` or
`llm-ollama:11434`.

Thinking is provider-neutral and request-aware:

- empty `LDS_AI_THINK` leaves thinking at the provider/model default;
- `LDS_AI_THINK=true|false` supplies the stack/container default;
- request-level `--think` / `--no-think` overrides it;
- `--think-auto` deliberately returns to provider/model default;
- strict JSON generation forces thinking off.

When thinking is explicit, the common request may emit compatible controls such as
`think=true|false` and `reasoning_effort=high|none`; provider-specific branching must
stay out of consumer commands.

## 5.2 Provider library

Keep a small reusable provider library such as:

```text
scripts/lib/ai-provider.sh
```

Responsibilities:

- normalize AI configuration;
- provider reachability and `/v1/models` preflight;
- deterministic model selection;
- chat completion;
- strict JSON completion;
- streaming;
- bounded connect/generation timeouts;
- positive/negative availability cache;
- response-size limits;
- thinking-control normalization;
- useful provider errors;
- no model lifecycle ownership.

Core helpers may expose:

```text
ai_available
ai_model
ai_generate
ai_generate_json
ai_stream
```

The provider library must not start, pull, unload, or remove models.

## 5.3 Retained safety behavior

The provider abstraction must retain:

- optional AI startup;
- bounded request/context/response bytes;
- credential redaction;
- sensitive/binary-file refusal;
- guarded untrusted-data prompt boundaries;
- no replay after partial streamed output;
- fail-closed deterministic model selection when multiple models are visible;
- no implicit cloud fallback.

## 5.4 Toolset / gitx

`gitx ai-commit` remains owned by Toolset. docker-tools must not copy or reimplement its
diff/prompt/commit logic.

docker-tools may only provide narrow environment/configuration delegation. If Toolset
lacks a generic OpenAI-compatible provider for the active `llm` runtime, the fix belongs
in Toolset rather than a duplicate implementation in docker-tools.

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
GITX_OLLAMA_URL=http://llm:11434
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
10. CI tests use a fake/mock OpenAI-compatible `llm` endpoint; never require a real model download.

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
- no LLM-specific Nginx routing belongs here; Nginx owns user-facing `llm.localhost` and provider-specific diagnostic routes.

## 8.5 `scripts/docker-templates/`

- preserve PHP/Node runtime generation;
- remove duplicate service-version/profile truth where possible;
- consume canonical service/runtime metadata;
- keep PHP/Node as locally-built developer runtimes, not published generic images;
- prepare optional environment injection for AI-aware developer tools without adding LLM lifecycle ownership here.

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
- add optional AI status indicator when the selected LLM provider service is reachable;
- future AI actions remain explicitly user-triggered.

## 8.13 `README.md`

Update after implementation stabilizes:

- define Tools as LocalDevStack control plane;
- document shared foundations;
- document AI as optional consumer functionality;
- document the selected LLM provider service and provider-neutral client contract;
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
8. fake OpenAI-compatible HTTP server tests for `ai-provider.sh`/`askai`;
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
LDS_AI_RUNTIME=<npu|cpu|nvidia|amd>
LDS_AI_MODEL=
```

and Docker-network connectivity to the selected provider service: `llm-fastflow` for `npu`, otherwise `llm-ollama`.

Tools-to-LLM requests stay inside the Docker network and resolve from `LDS_AI_RUNTIME`: `npu` uses `http://llm-fastflow:11434/v1`; `cpu|nvidia|amd` use `http://llm-ollama:11434/v1`.

User-facing browser/API access may remain available through Nginx-owned routes such as
`https://llm.localhost`; provider-specific hostnames are diagnostics/low-level surfaces only.

Tools does not create/start/remove whichever provider container currently owns the `llm` identity.

---

# 12. Acceptance criteria

The Tools hardening release is ready when:

1. permanent CI is green;
2. image builds from fresh rolling dependencies;
3. Scriptomatic/Toolset contracts match completed foundations;
4. no Ollama runtime exists inside Tools;
5. all existing Tools workflows remain functional without the optional `llm` service;
6. `askai`/AI-provider tests pass against a fake OpenAI-compatible endpoint;
7. Toolset-owned `gitx ai-commit` remains delegated without introducing provider-specific logic into docker-tools;
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

---

# 14. Additive extension — whole-ecosystem contract audit

This section is **additive only**. Sections 1–13 above remain unchanged and retain their original requirements and priority. The requirements below were found by reviewing the current `docker-tools` codebase together with the connected `infocyph/docker-runner`, `infocyph/docker-nginx`, `infocyph/docker-apache`, `infocyph/docker-llm-ollama`, and LocalDevStack integration contracts.

## 14.1 Treat connected images as one tested contract surface

`docker-tools` is not an isolated utility image. It generates configuration and control-plane state consumed by other LocalDevStack images, so CI must freeze the interfaces between them.

Maintain an explicit compatibility matrix covering:

- Tools -> Nginx: generated vhosts, TLS paths, FPM socket assumptions, proxy include names, streaming/WebSocket behavior and reserved localhost routes;
- Tools -> Apache: generated vhosts, `/app`, log paths, TLS/mTLS certificate paths, HTTP/2 and PHP-FPM proxy behavior;
- Tools -> Runner: cron/supervisor directories, generated config format and safe reload behavior;
- Tools -> selected LLM provider: `LDS_AI_RUNTIME=npu` targets `http://llm-fastflow:11434/v1`; `cpu|nvidia|amd` target `http://llm-ollama:11434/v1`, with no lifecycle ownership;
- Tools -> LocalDevStack: canonical service catalog, mounted state/config paths, network/service names, image compatibility and product-level orchestration ownership.

Compatibility tests should use the actual hardened sibling images or explicit tested refs, not reimplement their syntax/contracts with local mocks. Floating `latest` may still exist operationally, but a LocalDevStack release should record which image versions/digests were compatibility-tested together.

## 14.2 Docker socket/project-scope hardening

Tools currently has enough Docker access to inspect the entire host daemon. LocalDevStack-owned commands must default to the current LocalDevStack Compose project rather than silently falling back to all host containers.

Requirements:

- resolve the target stack primarily from `com.docker.compose.project` / `com.docker.compose.service` labels and the canonical LocalDevStack catalog;
- scope monitor discovery, status discovery and certificate SAN discovery to the current project/network by default;
- do not fall back to `docker ps -a` across the entire daemon merely because the project could not be inferred;
- provide an explicit `--all`/diagnostic opt-in only where host-wide inspection is genuinely useful;
- avoid inspecting unrelated containers for environment variables, credentials, aliases or mounted paths;
- prefer labels/catalog metadata over fuzzy container-name/image-substring matching;
- treat inability to determine the LocalDevStack project as a bounded degraded state rather than permission to widen scope.

Database/queue probes must not guess credentials. In particular, remove fixed credential fallbacks; missing credentials should result in a clear `not_configured`/`probe_unavailable` state. Secrets obtained for a probe must never appear in JSON output, logs or AI context.

## 14.3 TLS and key-material separation across images

Tools remains the certificate issuer, but the current shared-volume model should be tightened so consumers receive only the material required for their role.

Requirements:

- preserve the consumer-visible public trust path `/etc/share/rootCA/rootCA.pem`, but separate the mkcert private CA store from the public root export so Nginx/Apache/Mailpit never receive `rootCA-key.pem`;
- coordinate the backing-volume/mount split in LocalDevStack rather than changing the established consumer path arbitrarily;
- move toward role-specific TLS mounts so Nginx, Apache and Mailpit do not all receive every server/client/user private key merely because they share `/etc/mkcert` today;
- keep `lds-client-internal` available only to components that actually perform the Nginx -> Apache mTLS client role;
- treat the human/browser `lds-client-user.p12` bundle as sensitive credential material, not as a generic public artifact;
- place the user P12 export behind an explicit protected workflow and do not expose it through an unauthenticated admin endpoint;
- do not generate/export a passwordless P12 by default unless the final LocalDevStack UX has a deliberate, documented local-only protection model;
- add tests proving that private CA material is absent from consumer containers and that each consumer sees only its expected certificate/key set.

## 14.4 Admin-panel control-plane trust boundary

The admin panel can mutate hosts and Runner automation and can currently expose certificate artifacts. Treat it as a privileged local control-plane UI, not a passive dashboard.

Requirements:

- introduce a lightweight LocalDevStack-scoped authorization boundary for mutating APIs and sensitive downloads; a per-stack token/session contract is sufficient if it stays simple;
- require same-origin/CSRF protection for browser-triggered mutations;
- keep mutating operations on explicit POST/PUT/PATCH/DELETE paths and require visible confirmation for destructive actions;
- protect mTLS/P12 downloads separately from public root-CA downloads;
- centralize external process execution through one audited runner abstraction;
- eliminate direct `shell_exec()` and duplicate `proc_open()` implementations from pages/services once the shared runner is capable enough;
- add stdout/stderr byte caps to the process runner so a noisy command cannot exhaust the admin PHP process;
- make timeout termination clean up the complete spawned command where practical rather than only the immediate process;
- add baseline response hardening (`no-store`, content-type protection and appropriate frame/referrer/CSP policy) without turning this into a full web-framework project;
- never make the admin panel accessible through a host-published raw port by default; the intended user route remains the LocalDevStack/Nginx convenience route.

AI actions in the panel inherit this same authorization boundary and remain user-triggered only.

## 14.5 Transactional control-plane writes and rollback

Control-plane edits must not destroy the last valid state before the replacement has been rendered and validated.

### Host/vhost edits

Current host editing removes the existing host before the replacement is known-good. Change the implementation flow to:

1. normalize/validate the requested model;
2. render replacement artifacts into staging paths;
3. validate generated Compose/Nginx/Apache/FPM artifacts using the real target runtimes;
4. atomically replace the previous artifacts only after validation succeeds;
5. retain/restore the previous valid set if commit or downstream reload fails.

Create/edit/delete/recreate tests must cover partial failure and rollback.

### Runner automation edits

Cron/supervisor changes should similarly be staged before replacing active files. Validate the staged content, atomically install it, invoke the Runner reload contract, and restore the previous version if the reload rejects the new configuration.

### `env-store`

The JSON backend needs real concurrent-writer safety:

- create temporary files in the destination directory rather than generic `/tmp`, so the final rename is same-filesystem and atomic;
- use a bounded lock around read-modify-write operations;
- preserve intended ownership/mode when replacing the file;
- test simultaneous CLI/admin writes and malformed-store recovery behavior.

Also classify `/etc/share/state` explicitly. Ephemeral diagnostic/cache state may remain container-local; durable product configuration must live in a LocalDevStack-owned persisted/mounted location or the canonical service/config catalog rather than disappearing with a Tools container recreation.

## 14.6 Multi-architecture native artifact correctness

The publication plan requires amd64 + arm64, but every downloaded native executable must be architecture-aware before that can be trusted.

Requirements:

- use BuildKit `TARGETARCH`/`TARGETOS` (with explicit upstream-name mapping where required) for mkcert and any other downloaded native binary;
- remove the hard-coded `linux/amd64` mkcert fetch from the multi-arch path;
- verify release checksums/signatures where upstream provides them;
- verify the downloaded binary architecture and execute a version/smoke command inside each candidate architecture;
- make multi-arch publication fail if any native asset falls back to the wrong architecture;
- include resolved native tool versions and checksums in publication summaries alongside rolling base/dependency resolution.

Runtime metadata generation should also sort PHP/Node versions semantically/numerically rather than by plain string order so future versions such as `8.10` cannot be ordered incorrectly relative to `8.9`.

## 14.7 Reserved LocalDevStack routes are an ecosystem ABI

The hardened Nginx image owns predefined convenience routes such as `admin.localhost`, `llm.localhost`, and provider-specific diagnostic LLM routes. `mkhost` must not allow generated user hosts to shadow reserved product routes.

Requirements:

- reject collisions with LocalDevStack-reserved convenience hostnames during host creation/edit;
- source the reserved-route list from the canonical LocalDevStack catalog/route contract when that contract becomes available rather than maintaining another permanent hard-coded copy in Tools;
- keep `llm.localhost` and provider-specific diagnostic LLM hostnames fully Nginx-owned; Tools does not generate competing LLM vhosts;
- add a CI guard that renders every maintained Tools Nginx template against the actual hardened Nginx image and verifies every referenced include exists (`proxy_params`, timeout/buffer/streaming/WebSocket/H2/FastCGI snippets, etc.);
- validate Apache templates against the hardened Apache image and its loaded-module/TLS/mTLS contract;
- validate Runner scheduler paths against the hardened Runner image rather than assuming path compatibility.

## 14.8 AI provider safety, latency and deterministic behavior

Extend the provider layer with the following operational rules:

- separate a short provider/DNS/connect timeout from the potentially long generation timeout;
- cache positive/negative availability briefly so a missing optional `llm` service does not add repeated connection latency to every command/panel render;
- bound request bytes, response bytes and diagnostic/context bytes independently;
- retry safe reachability/preflight requests only; do not blindly replay a generation after partial streamed output;
- if `LDS_AI_MODEL` is empty, auto-select only when the provider state makes the choice deterministic; if multiple installed models are plausible, return a clear ambiguity error rather than silently choosing the first result;
- treat repository files, logs, diffs, config and monitor text as untrusted **data**, not as trusted provider/system instructions; prompt construction must keep the instruction boundary explicit;
- make redaction deterministic and test it with credential/token/URL/header/.env fixtures before any content reaches the provider;
- do not persist raw prompts/responses by default; optional debug telemetry should contain redacted metadata such as provider, model, duration, byte counts and a safe request/context hash rather than secret-bearing payloads;
- admin-panel generations should support streaming/cancellation or another bounded UX rather than tying up a PHP request for the full maximum generation timeout;
- keep fake-provider tests as the normal Tools CI path and add lightweight OpenAI-compatible protocol/schema coverage for both runtime-selected provider targets without requiring a real model download in every Tools check.

## 14.9 Tools-owned service health and lifecycle

Add a small Tools health contract that checks only services owned by this image.

The healthcheck should:

- verify the main notifier/control process is alive and its FIFO/runtime state is sane;
- verify the admin panel only when `ADMIN_PANEL_AUTOSTART=1`;
- surface a dead background admin process instead of leaving the container permanently "healthy" because `notifierd` is still PID 1;
- remain independent of Docker daemon reachability, database availability and selected LLM provider availability;
- keep AI strictly optional, so an absent LLM can never make Tools unhealthy.

The notifier TCP listener should remain an internal LocalDevStack transport by default. Do not publish it to the host unless explicitly requested; if future external exposure is supported, require authentication rather than relying on the current optional empty token.

## 14.10 Additional CI/acceptance gates from this audit

In addition to Sections 9 and 12, add focused gates for:

1. amd64 and arm64 native-tool execution (`mkcert`, lazydocker where applicable, Toolset commands);
2. isolation from an unrelated Docker Compose project running on the same daemon;
3. certificate SAN collection excluding unrelated host containers;
4. absence of `rootCA-key.pem` from Nginx/Apache/Mailpit consumer mounts;
5. protected admin mutation and sensitive-artifact endpoints;
6. centralized process execution with bounded output;
7. host-edit failure rollback preserving the previous working host;
8. cron/supervisor invalid-update rollback preserving the previous Runner config;
9. concurrent `env-store` writers without lost/corrupt updates;
10. rejection of reserved LocalDevStack hostnames including `llm.localhost` and provider-specific diagnostic LLM routes;
11. actual Nginx include/template ABI validation against the hardened Nginx image;
12. actual Apache/FPM/TLS template validation against the hardened Apache/runtime contract;
13. AI-disabled, provider-unreachable, ambiguous-model, redaction, oversized-context, timeout and interrupted-stream behavior;
14. Tools health remaining green with AI disabled/unavailable while failing when an enabled Tools-owned admin process dies.

These gates should be assigned to the existing implementation batches according to the component they protect rather than creating a separate fifth hardening phase.

---

# 15. Deterministic Document Structural Extraction & AI Review

## 15.1 Purpose

Add a reusable deterministic document-analysis capability to docker-tools so local AI
workflows do not ask small models to rediscover syntax and explicit structure that
software can extract mechanically.

The mechanical extractor must work with AI disabled. Optional AI review consumes its
normalized output and proposes additive semantic improvements.

## 15.2 Architectural ownership

### docker-tools owns

docker-tools may own generic, reusable developer tooling that can:

- scan explicitly supplied files/directories;
- mechanically parse document/config structure;
- normalize extracted structure into a stable JSON contract;
- resolve deterministic cross-document links/references;
- preserve source-file and source-span evidence;
- produce unresolved references without guessing;
- optionally hand the normalized result to the existing provider-neutral AI client for
  review/enrichment;
- validate LLM-proposed additions before returning them.

### Graphify owns

Graphify remains responsible for Graphify-specific behavior:

- building and merging the final Graphify graph;
- integrating document structure with its code AST graph;
- graph-specific node/edge schemas;
- graph clustering;
- community naming;
- semantic graph persistence;
- Graphify incremental manifests/cache behavior;
- deciding how deterministic document structure influences Graphify semantic extraction.

docker-tools should expose a useful generic intermediate representation rather than
forking Graphify internals.

### LocalDevStack owns

LocalDevStack should remain orchestration/provider selection:

- choose the active local LLM provider;
- expose `LDS_AI_RUNTIME` so Tools can select `llm-fastflow` or `llm-ollama` directly;
- make Tools available;
- mount an explicitly selected workspace when needed;
- avoid implementing document parsing itself.

### LLM images own

`docker-llm-fastflow` and `docker-llm-ollama` remain inference-only:

- model runtime;
- model storage;
- accelerator integration;
- OpenAI-compatible API;
- inference/runtime controls.

Do **not** add Pandoc, Sphinx, repository parsers, document AST tools, or graph logic to
LLM images.

## 15.3 Core principle

> Never ask the LLM to infer something that a deterministic parser can know.

Examples that should normally be mechanical:

- file identity;
- title;
- heading hierarchy;
- section containment;
- Markdown links;
- RST links and references;
- Sphinx roles/directives;
- includes;
- toctree relationships;
- code-block language;
- YAML/JSON/TOML keys;
- explicit URLs;
- explicit filenames;
- obvious symbol references;
- source spans;
- document-to-document references.

Examples that remain appropriate for the LLM:

- implicit architectural relationships;
- requirements and constraints expressed in prose;
- rationale;
- semantic equivalence;
- conceptual grouping;
- whether two differently named concepts refer to the same thing;
- implicit workflow/dependency interpretation;
- identifying important omissions in the deterministic graph.

## 15.4 Proposed user-facing capability

Introduce one generic command name, provisionally:

```text
docstruct
```

The final name can change during implementation, but there should be one primary command
instead of several format-specific commands.

Examples:

```bash
docstruct README.md
docstruct docs/
docstruct docs/ --format json
docstruct docs/ --include '*.md' --include '*.rst'
docstruct docs/ --output /tmp/project-docstruct.json
docstruct docs/ --resolve
docstruct docs/ --summary
```

Possible AI review integration:

```bash
aiops document-review --file /tmp/project-docstruct.json
```

or, if keeping the existing `review` surface is cleaner:

```bash
aiops review --file /tmp/project-docstruct.json --request "Review missing semantic relationships"
```

Do not make the deterministic extractor automatically invoke an LLM in the first
implementation. Deterministic extraction and semantic review should remain independently
testable.

## 15.5 Normalized intermediate contract

The extractor should output a versioned schema such as:

```json
{
  "schema": "docker-tools.docstruct/v1",
  "root": "/workspace",
  "files": [],
  "nodes": [],
  "edges": [],
  "unresolved_references": [],
  "warnings": []
}
```

### 15.5.1 File records

Each file record should include at minimum:

- normalized repository-relative path;
- detected format;
- content hash;
- byte size;
- parser used;
- parse status;
- warnings/errors;
- optional document title.

### 15.5.2 Node types

Initial node vocabulary should stay intentionally small:

- `document`;
- `section`;
- `heading`;
- `code_block`;
- `config_key`;
- `directive`;
- `reference`;
- `link_target`.

Do not attempt a large ontology in docker-tools.

### 15.5.3 Edge types

Initial deterministic relationships:

- `contains`;
- `links_to`;
- `references`;
- `includes`;
- `declares`;
- `configures`;
- `parent_of`.

If the relationship cannot be proved mechanically, leave it unresolved instead of
creating an inferred edge.

### 15.5.4 Evidence

Every mechanically created node/edge should retain evidence:

```json
{
  "source_file": "docs/runtime.rst",
  "line_start": 14,
  "line_end": 18
}
```

Where exact line mapping is unavailable from the selected parser, retain the closest
stable source locator available and clearly mark its precision.

### 15.5.5 Stable IDs

IDs must be deterministic and reproducible.

Preferred construction:

```text
<relative-path>#<normalized-anchor-or-structural-key>
```

Examples:

```text
README.md#installation
docs/runtime.rst#runtime-adapter
.github/ISSUE_TEMPLATE/bug_report.yml#labels
```

Avoid random UUIDs for structural nodes.

## 15.6 Format strategy

### 15.6.1 Markdown

Mechanically extract:

- ATX/setext headings;
- hierarchy;
- links;
- anchors where available;
- images as references only;
- fenced/indented code blocks and language tags;
- lists;
- tables;
- blockquotes;
- explicit HTML links;
- referenced paths.

Do not turn every paragraph into a node.

### 15.6.2 reStructuredText

Mechanically extract:

- document title/section hierarchy;
- links/targets;
- substitutions;
- includes;
- toctree entries;
- directives;
- roles;
- Sphinx references such as:
  - `:doc:`;
  - `:ref:`;
  - `:class:`;
  - `:func:`;
  - `:meth:`;
  - `:mod:`;
- code blocks and languages;
- explicit source/document references.

RST/Sphinx handling is a high-value part of this plan because these constructs encode
relationships that an LLM should not need to rediscover.

### 15.6.3 YAML / JSON / TOML

Mechanically extract:

- object/key hierarchy;
- scalar metadata;
- arrays;
- well-known metadata fields when detection is reliable;
- explicit file/path/URL references.

The generic representation should not hard-code GitHub issue-template semantics into
the base parser. Optional recognizers may annotate known formats later.

### 15.6.4 INI/config

Start conservative:

- sections;
- keys;
- explicit values where safe;
- path/URL references.

Never treat config values as executable input.

## 15.7 Parser/tooling decision

A short implementation spike should compare the following options before locking
dependencies into the image.

### Option A — Pandoc-centered

Use Pandoc JSON AST for Markdown and RST normalization.

Advantages:

- one mature parser for both formats;
- normalized AST;
- good structural fidelity;
- avoids custom Markdown/RST parsers.

Costs:

- potentially significant Alpine image-size increase;
- Pandoc is a comparatively large runtime dependency;
- Sphinx-specific roles/directives may still need an auxiliary scanner.

### Option B — small static helper

Build a small dedicated binary in a multi-stage build and copy only the final executable
into the runtime image.

Preferred implementation language for this option should be chosen based on parser
library maturity and final binary size, not language preference.

Advantages:

- controlled runtime footprint;
- no Python runtime requirement;
- one versioned output contract;
- easier security/resource controls.

Costs:

- more implementation/maintenance responsibility;
- Markdown and especially RST parser quality must be verified carefully.

### Option C — MyST / m2r2 / conversion-oriented Python tooling

Evaluate the current Python documentation ecosystem explicitly:

- MyST-Parser: strong Sphinx/Docutils Markdown integration and rich directive/role support,
  but it is primarily a Sphinx parser and brings Python + Sphinx + Docutils dependencies;
- m2r2: lightweight Markdown-to-RST conversion/Sphinx extension, useful as a compatibility
  reference but not a normalized structural AST by itself;
- md-rst: conversion wrapper around Pandoc, so it does not remove Pandoc's footprint.

These tools should be benchmarked for what structural information they expose, not merely
whether they can convert one markup language into another.

### Option D — packaged format tools

Compose existing Alpine-packaged CLIs plus `jq`/`yq`.

Advantages:

- minimal custom code.

Costs:

- inconsistent AST shapes;
- harder stable source-span behavior;
- likely weak RST/Sphinx coverage.

### Decision rule

Benchmark at least:

1. parsing fidelity;
2. RST/Sphinx reference coverage;
3. source line/span fidelity;
4. runtime/image-size cost;
5. cold execution time;
6. maintenance/security surface.

Do not add Python solely to implement this feature unless the evaluation proves that a
Python/docutils path is materially better than the alternatives. The goal is to avoid
another bespoke Python compatibility layer.

## 15.8 Recommended initial direction

Start with:

1. Pandoc feasibility benchmark for Markdown/RST;
2. compare MyST-Parser and m2r2 specifically for Sphinx/RST/Markdown structural fidelity
   and dependency footprint;
3. small deterministic Sphinx/RST role/directive scanner where generic converters lose
   explicit directives such as includes or typed references;
4. existing `jq`/`yq` for JSON/YAML normalization where appropriate;
5. explicit benchmark of final image-size growth.

Current Batch-0 evidence already shows Pandoc preserves basic Markdown/RST structure and
Sphinx symbol text, but does not resolve the representative `.. include::` fixture.
That means Pandoc alone is insufficient for the target contract.

If the Python/Sphinx or Pandoc dependency cost is excessive, prefer a small extractor
built from dependencies already present in docker-tools (PHP is already shipped) or a
small static helper rather than accumulating another large runtime stack.

## 15.9 Deterministic reference resolution

Resolution should be a separate stage from parsing.

### 15.9.1 Document references

Resolve mechanically where possible:

- relative Markdown links;
- RST `:doc:`;
- RST `:ref:`;
- include paths;
- toctree members;
- explicit repository-relative paths.

### 15.9.2 Symbol references

For things like:

```rst
:class:`RuntimeManager`
:meth:`RuntimeAdapter.start`
```

the deterministic extractor should emit:

- reference type;
- symbol text;
- source location;
- normalized candidate target;

without pretending it can prove the final code symbol if no code index was supplied.

A future Graphify integration can resolve these against Graphify's code AST nodes.

### 15.9.3 No guessing

Unresolved references belong in:

```json
"unresolved_references": []
```

They should not silently become edges.

## 15.10 LLM review contract

The LLM should review deterministic output, not regenerate it from scratch.

Preferred review input:

```text
DETERMINISTIC STRUCTURE
<normalized nodes/edges/unresolved refs>

RELEVANT SOURCE PASSAGES
<bounded source excerpts only where needed>

TASK
Add only semantic information that cannot be derived mechanically.
```

Preferred LLM output should be additive:

```json
{
  "add_nodes": [],
  "add_edges": [],
  "corrections": [],
  "unresolved": []
}
```

Do not ask the model to reproduce all deterministic nodes/edges.

### 15.10.1 Evidence rule

Every LLM proposal must include:

- source file;
- source span/excerpt locator where possible;
- reason;
- confidence.

### 15.10.2 Validation

Before returning LLM enrichment:

- reject malformed JSON;
- reject references to nonexistent source files;
- reject edges pointing at unknown node IDs unless the added node is in the same patch;
- reject unsupported relationship types;
- preserve deterministic data as authoritative.

If review fails, the mechanical result remains valid.

## 15.11 Safety and trust boundary

Document parsing must treat repositories as untrusted input.

Requirements:

- no execution of code blocks;
- no execution of Sphinx directives;
- no shell expansion;
- no template evaluation;
- no network fetches by default;
- no following external URLs;
- no escaping the supplied root through `../`;
- bounded file size;
- bounded total corpus size;
- bounded include depth;
- bounded reference count;
- bounded parse time;
- symlink handling explicit and root-confined;
- binary/secret-sensitive inputs refused through the existing safe-file policy where
  the AI path is involved.

Deterministic parsing may inspect non-secret config files without sending them to the
LLM. AI review must continue to use docker-tools' existing redaction and safe-input
boundary.

## 15.12 Workspace model

Do not silently scan arbitrary host repositories.

The command should operate on:

- explicit file paths;
- explicit directories;
- an explicitly mounted workspace.

Default scan behavior should respect:

- common VCS/vendor/build exclusions;
- `.gitignore` where practical;
- explicit include/exclude flags.

A repository mount should be read-only by default for analysis workflows.

## 15.13 Performance and incremental behavior

The deterministic stage should be cheap enough to run before every semantic review.

Recommended cache key:

```text
schema-version + parser-version + file-content-hash
```

Cache should be optional and disposable.

Do not make correctness depend on cache presence.

Useful metrics:

- files scanned;
- files parsed;
- cache hits/misses;
- nodes/edges produced;
- unresolved reference count;
- parse duration by format.

## 15.14 Integration with existing docker-tools AI

Reuse the existing provider-neutral AI plumbing:

- `LDS_AI_RUNTIME` as the provider-selection source of truth;
- `npu` -> `http://llm-fastflow:11434/v1`;
- `cpu|nvidia|amd` -> `http://llm-ollama:11434/v1`;
- bounded requests;
- thinking controls;
- redaction;
- response-size caps;
- no output auto-execution.

Do not add provider-specific FastFlow/Ollama logic to the document extractor.

The deterministic extractor itself should work with AI disabled.

## 15.15 Graphify integration boundary

The initial docker-tools release should **not** patch Graphify output directly.

Instead expose the normalized deterministic artifact so Graphify can later consume it
through one of these paths:

1. upstream Graphify adds a native deterministic-document adapter;
2. Graphify accepts a normalized sidecar/pre-extracted document graph;
3. LocalDevStack/host workflow invokes both tools and hands the sidecar to Graphify.

Preferred long-term option: upstream Graphify owns the merge because it already owns the
code AST and final graph schema.

Do not make docker-tools maintain a Graphify-specific fork.

## 15.16 Image-size and dependency budget

Before adding any parser dependency, record:

- current compressed image size;
- current unpacked image size;
- dependency delta;
- startup/healthcheck impact;
- architecture availability for amd64/arm64;
- CVE/security maintenance implications.

Suggested acceptance target:

- no meaningful startup regression;
- parser dependency available on all currently published architectures;
- image growth justified by measurable reduction in LLM work/error rate.

If Pandoc adds excessive image weight, the static-helper option should be preferred.

## 15.17 Testing strategy

### 15.17.1 Unit/contract fixtures

Include representative fixtures:

- simple Markdown;
- nested Markdown headings;
- Markdown links/anchors;
- RST headings;
- RST include;
- RST toctree;
- RST Sphinx roles;
- YAML issue template;
- JSON config;
- TOML config;
- broken/malformed files;
- symlink escape attempt;
- oversized input;
- include recursion.

### 15.17.2 Determinism tests

The same input must produce byte-for-byte equivalent normalized structure after sorting
canonical collections.

### 15.17.3 Source evidence tests

Verify line/source locators for every supported structural type.

### 15.17.4 Security tests

Verify:

- no external fetch;
- no directive execution;
- no traversal outside root;
- include depth cap;
- size caps;
- secret-sensitive AI review refusal.

### 15.17.5 AI review tests

Using the existing fake OpenAI-compatible endpoint:

- deterministic artifact remains unchanged;
- valid additive enrichment is accepted;
- malformed enrichment is rejected;
- unknown node/edge targets are rejected;
- AI unavailable still returns deterministic results successfully.

### 15.17.6 Release gate

The final image gate should verify:

- `docstruct --help`;
- one Markdown extraction;
- one RST extraction;
- one YAML extraction;
- JSON schema validity;
- no LLM required for deterministic mode.

## 15.18 Proposed implementation batches

### Batch 0 — benchmark and dependency decision

- capture current image-size baseline;
- evaluate Pandoc Markdown/RST AST fidelity;
- evaluate RST/Sphinx role/directive coverage;
- evaluate static-helper alternative;
- document selected parser stack and size delta.

Exit criteria:

- parser/toolchain choice is justified with measurements;
- no implementation dependency is added before this gate.

### Batch 1 — normalized schema and CLI shell

- define `docker-tools.docstruct/v1`;
- add `docstruct --help`;
- path/root validation;
- JSON output;
- canonical ordering;
- deterministic error/warning model.

Exit criteria:

- empty/minimal fixtures produce stable valid output;
- no AI dependency.

### Batch 2 — Markdown extraction

- document/title/section hierarchy;
- links;
- anchors;
- code blocks;
- source evidence;
- tests.

Exit criteria:

- Markdown fixture suite passes deterministically.

### Batch 3 — RST/Sphinx extraction

- headings;
- directives;
- roles;
- includes;
- toctree;
- explicit targets/references;
- source evidence;
- tests.

Exit criteria:

- core Sphinx relationships are mechanically visible without AI.

### Batch 4 — structured config extraction

- YAML;
- JSON;
- TOML;
- conservative INI/config handling;
- key hierarchy;
- explicit references.

Exit criteria:

- config fixture suite passes;
- no values are executed/interpreted as code.

### Batch 5 — deterministic resolver

- document links;
- RST refs/docs;
- includes;
- toctree;
- unresolved reference inventory;
- canonical target IDs.

Exit criteria:

- resolvable links become deterministic edges;
- unresolved links remain explicit without guessing.

### Batch 6 — security/resource hardening

- traversal;
- symlinks;
- include recursion;
- corpus/file caps;
- timeouts;
- no-network guarantee;
- malformed input behavior.

Exit criteria:

- adversarial fixture suite passes.

### Batch 7 — optional AI review

- bounded normalized context;
- additive enrichment schema;
- provider-neutral `llm` use;
- validation;
- evidence/confidence;
- deterministic output survives AI failure.

Exit criteria:

- AI never replaces or corrupts mechanical extraction.

### Batch 8 — Graphify interoperability research

- prototype sidecar handoff;
- identify minimum upstream Graphify change;
- compare:
  - Graphify raw semantic extraction;
  - deterministic structure + LLM review;
- measure hollow/malformed/retry rate;
- measure runtime/token reduction.

Exit criteria:

- clear recommendation for the upstream Graphify integration path.

### Batch 9 — documentation/release hardening

- README;
- command reference;
- architecture docs;
- release gate;
- amd64/arm64 validation;
- image-size comparison;
- final security review.

## 15.19 Evaluation metrics

The plan should be judged on measurable improvement, not merely parser completeness.

Compare a representative repository before/after:

- LLM semantic requests;
- input tokens;
- output tokens;
- wall-clock time;
- hollow responses;
- malformed responses;
- retries;
- files with no semantic coverage;
- deterministic nodes/edges produced;
- unresolved reference count;
- final graph coverage;
- final image-size delta.

For the motivating TalkingBytes-style workload, the desired direction is:

```text
most syntax/structure -> deterministic
small semantic delta  -> LLM
```

rather than:

```text
all docs -> LLM -> complete graph
```

## 15.20 Non-goals

Do not use this effort to:

- turn docker-tools into a second Graphify;
- embed an LLM in docker-tools;
- move inference dependencies into Tools;
- move document parsers into LLM images;
- execute repository content;
- implement a generic compiler/parser framework;
- infer semantic relationships mechanically when they are not explicit;
- automatically rewrite repository documentation;
- automatically mutate Graphify output before an explicit interoperability contract exists.

## 15.21 Definition of done

This initiative is ready for release when:

1. docker-tools can deterministically extract Markdown and RST structure from an
   explicitly supplied workspace;
2. YAML/JSON/TOML structural extraction is supported;
3. explicit cross-document references are resolved where provable;
4. unresolved references remain explicit instead of guessed;
5. every structural fact retains source evidence;
6. extraction works with AI completely disabled;
7. optional AI review adds only validated semantic deltas;
8. malformed/unavailable AI never invalidates deterministic results;
9. parser dependencies remain acceptable for both published architectures;
10. release/security tests cover hostile inputs;
11. the final Graphify interoperability recommendation is documented;
12. LLM images remain inference-only.

## 15.22 Internal LLM transport rule

Any optional AI review launched from docker-tools must resolve the direct Docker-network
endpoint from `LDS_AI_RUNTIME`:

```text
npu             -> http://llm-fastflow:11434/v1
cpu|nvidia|amd  -> http://llm-ollama:11434/v1
```

Do not use `llm.localhost` for Tools-to-LLM traffic. The localhost/TLS route remains
user-facing infrastructure only.

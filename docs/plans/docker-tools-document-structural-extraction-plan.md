# docker-tools — Deterministic Document Structural Extraction & AI Review Plan

Status: planning only  
Implementation branch: `plan/document-structural-extraction`  
Base: `main`

## 1. Goal

Add a reusable deterministic document-analysis capability to `docker-tools` so local AI
workflows do not need to ask a small model to rediscover syntax and explicit structure
that software can extract mechanically.

The target flow is:

```text
repository / selected files
          |
          v
   deterministic parser
          |
          v
 normalized structural JSON
          |
          +--------------------+
          |                    |
          v                    v
 deterministic consumers   optional LLM review
                               |
                               v
                       additions / corrections
```

The first implementation target is documentation and configuration content commonly
encountered in developer repositories:

- Markdown;
- reStructuredText;
- YAML;
- JSON;
- TOML;
- INI/config-style files where practical.

The design should make Markdown/RST analysis cheap and reliable enough that the LLM is
used for **semantic interpretation**, not syntax parsing.

## 2. Architectural ownership

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
- expose the common `llm` endpoint;
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

## 3. Core principle

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

## 4. Proposed user-facing capability

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

## 5. Normalized intermediate contract

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

### 5.1 File records

Each file record should include at minimum:

- normalized repository-relative path;
- detected format;
- content hash;
- byte size;
- parser used;
- parse status;
- warnings/errors;
- optional document title.

### 5.2 Node types

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

### 5.3 Edge types

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

### 5.4 Evidence

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

### 5.5 Stable IDs

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

## 6. Format strategy

## 6.1 Markdown

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

## 6.2 reStructuredText

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

## 6.3 YAML / JSON / TOML

Mechanically extract:

- object/key hierarchy;
- scalar metadata;
- arrays;
- well-known metadata fields when detection is reliable;
- explicit file/path/URL references.

The generic representation should not hard-code GitHub issue-template semantics into
the base parser. Optional recognizers may annotate known formats later.

## 6.4 INI/config

Start conservative:

- sections;
- keys;
- explicit values where safe;
- path/URL references.

Never treat config values as executable input.

## 7. Parser/tooling decision

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

### Option C — packaged format tools

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

## 8. Recommended initial direction

Start with:

1. Pandoc feasibility benchmark for Markdown/RST;
2. small deterministic Sphinx/RST role/directive scanner if Pandoc does not preserve
   enough semantic detail;
3. existing `jq`/`yq` for JSON/YAML normalization where appropriate;
4. explicit benchmark of final image-size growth.

If Pandoc's image cost is unacceptably high, switch to a small static helper rather than
accumulating several scripting runtimes.

## 9. Deterministic reference resolution

Resolution should be a separate stage from parsing.

### 9.1 Document references

Resolve mechanically where possible:

- relative Markdown links;
- RST `:doc:`;
- RST `:ref:`;
- include paths;
- toctree members;
- explicit repository-relative paths.

### 9.2 Symbol references

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

### 9.3 No guessing

Unresolved references belong in:

```json
"unresolved_references": []
```

They should not silently become edges.

## 10. LLM review contract

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

### Evidence rule

Every LLM proposal must include:

- source file;
- source span/excerpt locator where possible;
- reason;
- confidence.

### Validation

Before returning LLM enrichment:

- reject malformed JSON;
- reject references to nonexistent source files;
- reject edges pointing at unknown node IDs unless the added node is in the same patch;
- reject unsupported relationship types;
- preserve deterministic data as authoritative.

If review fails, the mechanical result remains valid.

## 11. Safety and trust boundary

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

## 12. Workspace model

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

## 13. Performance and incremental behavior

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

## 14. Integration with existing docker-tools AI

Reuse the existing provider-neutral AI plumbing:

- `LDS_AI_PROVIDER=llm`;
- `LDS_AI_URL=http://llm:11434`;
- bounded requests;
- thinking controls;
- redaction;
- response-size caps;
- no output auto-execution.

Do not add provider-specific FastFlow/Ollama logic to the document extractor.

The deterministic extractor itself should work with AI disabled.

## 15. Graphify integration boundary

The initial docker-tools release should **not** patch Graphify output directly.

Instead expose the normalized deterministic artifact so Graphify can later consume it
through one of these paths:

1. upstream Graphify adds a native deterministic-document adapter;
2. Graphify accepts a normalized sidecar/pre-extracted document graph;
3. LocalDevStack/host workflow invokes both tools and hands the sidecar to Graphify.

Preferred long-term option: upstream Graphify owns the merge because it already owns the
code AST and final graph schema.

Do not make docker-tools maintain a Graphify-specific fork.

## 16. Image-size and dependency budget

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

## 17. Testing strategy

### Unit/contract fixtures

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

### Determinism tests

The same input must produce byte-for-byte equivalent normalized structure after sorting
canonical collections.

### Source evidence tests

Verify line/source locators for every supported structural type.

### Security tests

Verify:

- no external fetch;
- no directive execution;
- no traversal outside root;
- include depth cap;
- size caps;
- secret-sensitive AI review refusal.

### AI review tests

Using the existing fake OpenAI-compatible endpoint:

- deterministic artifact remains unchanged;
- valid additive enrichment is accepted;
- malformed enrichment is rejected;
- unknown node/edge targets are rejected;
- AI unavailable still returns deterministic results successfully.

### Release gate

The final image gate should verify:

- `docstruct --help`;
- one Markdown extraction;
- one RST extraction;
- one YAML extraction;
- JSON schema validity;
- no LLM required for deterministic mode.

## 18. Proposed implementation batches

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

## 19. Evaluation metrics

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

## 20. Non-goals

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

## 21. Definition of done

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

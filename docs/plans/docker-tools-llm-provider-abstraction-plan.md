# docker-tools — Common LLM Provider Abstraction Plan

Status: implementation branch `llm-provider-abstraction`

## Goal

Make docker-tools consume one provider-neutral LocalDevStack LLM identity:

```text
http://llm:11434/v1
```

The active backend may be Ollama or FastFlow. docker-tools must not need to know which
runtime owns the `llm` alias.

## Transport contract

Use only the common OpenAI-compatible surface:

- `GET /v1/models`;
- `POST /v1/chat/completions`;
- OpenAI SSE streaming with `data: ...` and `data: [DONE]`.

Do not use Ollama-native `/api/tags`, `/api/generate`, or `/api/chat` from the
common Tools client.

Defaults:

```text
LDS_AI_PROVIDER=llm
LDS_AI_URL=http://llm:11434
```

## Behavior retained

The provider abstraction must retain the existing safety contract:

- optional AI startup;
- bounded connect/preflight/generation timeouts;
- positive and negative availability cache;
- deterministic model selection;
- fail closed when multiple models are visible and no model is configured;
- request/context/response byte limits;
- credential redaction;
- sensitive/binary-file rejection;
- guarded untrusted-data prompt boundaries;
- no replay after partial streaming output.

## gitx ai-commit

`gitx ai-commit` remains owned by Toolset. docker-tools must **not** copy, fork, or
reimplement its staged-diff, prompt, or commit-flow logic.

Current Toolset supports `ollama|gemini|auto`, not a generic OpenAI provider. Therefore
docker-tools only performs a narrow wrapper configuration when `gitx ai-commit` is
invoked:

- preserve the installed Toolset `gitx` binary and delegate the command unchanged;
- force `GITX_AI_PROVIDER=ollama` so LocalDevStack can never fall back to Gemini/cloud;
- point `GITX_OLLAMA_URL` at the selected LocalDevStack `llm` service URL;
- reuse the deterministic model chosen by the Tools provider preflight;
- unset Gemini credentials in the delegated child process.

When `llm` points to FastFlow, Toolset's current Ollama-native `ai-commit` transport is
not compatible and may fail locally. Fixing that belongs in Toolset by adding a generic
OpenAI-compatible provider; docker-tools must not introduce a second `ai-commit`
implementation to work around it.

## Reserved routes

The admin host manager must reserve:

```text
llm.localhost
llm-ollama.localhost
llm-fastflow.localhost
```

so application-host mutations cannot collide with LocalDevStack AI routing.

## Validation

Tests must use a provider-neutral OpenAI fake endpoint and verify:

1. `/v1/models` availability/model selection;
2. non-stream chat completion;
3. JSON prompting + local validation;
4. OpenAI SSE streaming and no-replay failure semantics;
5. redaction and input limits;
6. `askai` through the common provider;
7. Toolset-owned `gitx ai-commit` delegation with cloud fallback disabled;
8. all three reserved LLM hostnames;
9. no Ollama-native API dependency in the shared `askai`/`aiops` client.

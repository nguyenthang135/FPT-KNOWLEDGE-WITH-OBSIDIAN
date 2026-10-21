# FPT Knowledge AI gateway

Not used or deployed by Windows 1.0.1, which uses the owner's selected direct
Groq compiled-key design. This optional server source is not a runtime dependency.

Deployment is pending: no project hosting account, HTTPS hostname or rotated
production key has been supplied. This source is locally tested, not AI-live.

Requires Node 22+ and a **single process/replica** on a project-owned server with
persistent storage. Run `node gateway.mjs` behind an HTTPS reverse proxy, binding
only to loopback. Set `GROQ_API_KEY` using the host's encrypted secret manager.
Never pass its value as a CLI argument or compile it into Flutter. Rotate the
previously exposed key before deployment. No client token is needed.

Set `TRUST_LOCAL_PROXY=1` only when the trusted reverse proxy replaces both
`X-Real-IP` and `X-Forwarded-Proto` and cannot be bypassed. Otherwise all public
users share the proxy's IP limit. Persist `QUOTA_FILE` on private writable storage.
Do not deploy with multiple replicas: quota state is intentionally single-host.

Limits: 64 KiB request, 48,000 UTF-8 content bytes, 700 output tokens, 4 concurrent
upstream requests, 6 requests/minute/IP, 40/day/IP, 30/minute globally, 500/day
globally, and 1,000,000 conservatively reserved token units/day. Reservations
include input bytes plus output cap and overhead; failures also consume quota.
Daily quota survives restart; minute limits reset. Storage errors fail closed.
Only POST `/api/ai/chat` is forwarded to the fixed Groq model and endpoint.
`GET /health` reports readiness without credentials. Errors contain no provider
body, key, prompt or stack. No request body or IP is logged; daily IP hashes are
stored for rate limiting. HTTP metadata may still appear in host/proxy logs.

An anonymous endpoint can be abused through rotating IPs. Global caps bound
usage but are not authentication or a monetary guarantee. Verify actual Groq
organization limits, host pricing and billing alerts before enabling public AI.
No free-hosting or unlimited-user claim is made. Add identity/distributed rate
limiting before scaling beyond this conservative single-server setup.

After deployment, verify Vietnamese answer and planner requests, controlled 429,
timeouts, and offline fallback from a packaged Windows app with no Groq env vars.
Then build with `--dart-define=FPT_AI_GATEWAY_URL=https://<actual-host>/api/ai/chat`.
All planner and answer calls use that endpoint and omit Authorization headers.
Release builds ignore local Groq keys. Never ship the illustrative URL above.

Test locally: `node --test server/groq-gateway/gateway.test.mjs` from the repo root.

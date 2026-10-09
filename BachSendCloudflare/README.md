# B Send v0.4 Online relay — technical preview

This standalone Cloudflare Worker is intended to power B Send iPhone-to-PC connections across unrelated networks. The worker name matches the user's deployed Worker: **bachsend-relay**.

## Deployment (Cloudflare Workers Builds)

1. Open Cloudflare **Workers & Pages > bachsend-relay > Settings > Builds > Connect**.
2. Authorize GitHub and connect the repository containing this folder.
3. Set the production branch to bachsend-hybrid-v04 and **Root directory** to \`BachSendCloudflare\` (do not point at repository root).
4. Use deploy command \`npx wrangler deploy\`. Worker name in \`wrangler.jsonc\` must remain \`bachsend-relay\`.
5. Once built, GET \`https://bachsend-relay.mrbach222.workers.dev/api/health\` should return \`{"status":"ready",...}\`, not Hello World.

If Builds cannot select the correct branch or root directory, do not deploy the repository root; pause and correct the configuration. Deployment also creates the SQLite-backed Durable Object using the declarative \`exports\` entry in \`wrangler.jsonc\`.

## API specification (for iOS native implementation)

- POST \`/api/session\` → \`{room, expiresAt, ownerWebSocketURL, guestURL}\`
- iOS app connects to \`ownerWebSocketURL\` using \`URLSessionWebSocketTask\`.
- PC opens \`guestURL\`, which uses a fragment token (not sent as HTTP referrer).
- The paired sockets exchange JSON control messages \`{type:"file-start",id,name,size}\`, \`{type:"file-end",id}\`, \`{type:"file-cancel"}\`; file payload is binary WebSocket frames of at most 64 KiB.
- 1 owner and 1 PC per room, with 1-hour TTL. Browser preview currently caps each file at 50 MiB.

## Security, privacy, and current limitations

This is **not production-ready** and must not be used for customer, banking or work-confidential files. WebSocket is TLS-protected but file content is not yet end-to-end encrypted. The relay does not persist file payloads. The public endpoint currently lacks global abuse-rate limits and production tracing. In-browser receiver builds a Blob in memory and therefore caps file size. Browser confirmation of complete uploads will require final recipient ACK (not yet part of the protocol). The iPhone client integration is not yet deployed, and these endpoints alone cannot transfer files to/from B Send.

Add an audited chunked E2E transport, origin/session validation, bandwidth quotas, abuse prevention, typed transfer acknowledgements, expiry/revocation, PC/iOS reconnect/resume and real-device tests before general release. Only use with authorized networks and files.

### Local verification

Run \`npm install\` then \`npm test\` and \`npx wrangler deploy --dry-run\`. Dry run does not deploy the worker.

## Deployment check — Cloudflare

If `/api/health` still responds with `Hello World!`, the last manually deployed starter Worker is still receiving traffic. Check the Cloudflare Worker **Settings → Builds** GitHub production branch (`bachsend-hybrid-v04`) and deploy command (`cd BachSendCloudflare && npx wrangler deploy`). A new push to this branch should trigger a Workers Build; check its success/error log under **Deployments → Builds**, then retest `/api/health` after a successful production deployment. Do not delete or recreate the Worker to resolve this state. This is a technical preview only; native iOS pairing and end-to-end encryption are not completed.

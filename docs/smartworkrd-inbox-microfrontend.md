# Smart Work RD Inbox — Microfrontend Spike

## Status

Isolated proof of concept on the `smartworkrd/inbox-microfrontend-spike` branch.
Pinned to Chatwoot Community 4.19.1. This is not a production integration.

## What this spike adds

- A dedicated `/smartworkrd/inbox` route rendered by Chatwoot's existing Rails layout.
- A Vue entrypoint with an explicit `mount(element, options)` and `unmount(element)` lifecycle.
- A memory-history router containing only the conversation routes needed by the inbox.
- The existing Chatwoot `ConversationView` mounted directly, without the Chatwoot dashboard sidebar or a second top-level navigation.
- A global bridge named `window.SmartWorkRDInbox` so a React host can load the entrypoint and call its lifecycle methods in a later integration phase.

## Local smoke test

1. Start Chatwoot using its normal development instructions.
2. Sign in to Chatwoot in the same browser origin.
3. Open `/smartworkrd/inbox`. An optional `?account_id=123` selects an account the signed-in Chatwoot user already belongs to.
4. Verify the conversation list, opening a conversation, sending a test message, and realtime updates.
5. Navigate away and call `window.SmartWorkRDInbox.unmount()` from the browser console to verify teardown.

The route uses Chatwoot's existing `cw_d_session_info` authentication cookie. The account ID is checked against the signed-in user's account list and route permissions before the inbox is mounted.

## Host contract

The entrypoint exposes:

```js
const handle = await window.SmartWorkRDInbox.mount(container, {
  accountId: 123,
});

// Later, when the React route unmounts:
handle.unmount();
// or:
window.SmartWorkRDInbox.unmount(container);
```

The host must load the built `smartworkrd-inbox` Vite entrypoint and its CSS from the Chatwoot deployment. This spike does not yet publish a stable asset-manifest endpoint for a remote host.

## Explicitly not implemented

- Supabase-to-Chatwoot single sign-on or one-time identity tickets.
- Tenant/account provisioning or canonical user mapping.
- Cross-origin cookie, CORS, CSP, or asset-host configuration.
- A stable host-side loader in the Smart Work RD Next.js application.
- Twenty integration.
- Production deployment, real customer channels, or production credentials.

Do not connect this route to customer traffic until the identity broker, tenant isolation, asset loading, cross-origin behavior, and staging tests are implemented and reviewed.

## License boundary

This spike imports Community code only. Keep the root MIT notices and third-party notices. Do not import code from `enterprise/` or files marked Enterprise without a separate written license.


## Smart Work RD visual contract

The microfrontend imports a dedicated scoped stylesheet at `app/javascript/smartworkrd/inbox.scss`. It includes Chatwoot utility classes and color tokens without importing the global dashboard stylesheet, so it does not replace the host's document font or global body styles.

- The mount root uses the Smart Work RD light palette: gray canvas, white surfaces, charcoal text, and forest-green primary actions.
- The Chatwoot dark-mode class is removed for this route; the CRM host owns the visual theme.
- The Tailwind content scan includes the Smart Work RD Vue root.
- The host remains the only owner of navigation, tenant/business switching, and account/session controls.

This is a visual alignment layer, not a completed remote asset loader or SSO integration.


## SSO broker contract

The Chatwoot fork now exposes `POST /smartworkrd/sso/consume`. It accepts a signed HS256 ticket from the Smart Work RD API and:

- Verifies issuer, audience, expiry, origin, CRM role, mapped Chatwoot user and account membership.
- Rejects expired or replayed tickets using a unique `jti` record in the Chatwoot database.
- Creates a normal Devise Token Auth credential and returns its headers in a `no-store` JSON response.
- Does not place the credential in a URL or log it. The host is responsible for storing the returned auth header object in its own `cw_d_session_info` cookie, which the Chatwoot frontend reads.

The CRM API issues tickets from `POST /tenants/:tenantId/integrations/chatwoot/launch-ticket` after checking tenant membership, business access, role, account mapping and user mapping. Tenant owners/admins configure the mappings through the CRM API. A successful browser handshake should be followed by the CRM `confirm` endpoint to mark the integration connected.

### Required Chatwoot environment

- `SMARTWORKRD_SSO_SECRET`: same random secret as CRM `CHATWOOT_SSO_SECRET`, minimum 32 bytes.
- `SMARTWORKRD_SSO_ISSUER`: defaults to `smartworkrd-crm`.
- `SMARTWORKRD_SSO_AUDIENCE`: defaults to `chatwoot`.
- `SMARTWORKRD_ALLOWED_ORIGIN`: exact CRM origin, e.g. `https://crm.smartworkrd.com`, without a trailing slash.
- `ENABLE_API_CORS=true`: allows the configured CRM origin to call Chatwoot APIs.
- `FORCE_SSL=true`: required in production.

The CORS initializer allows the configured origin for the SSO endpoint, Chatwoot APIs and Action Cable. It does not enable wildcard API CORS when the Smart Work RD origin is configured.

### Host responsibilities still pending

- Obtain a launch ticket from the CRM API using the current Supabase bearer token.
- POST the ticket to this endpoint, then store the returned `auth` object as `cw_d_session_info` on the CRM origin with its expiry.
- Set `window.chatwootConfig.apiHost` to the Chatwoot origin before loading the entrypoint.
- Resolve the production Vite manifest/asset URLs and load the JavaScript and CSS dynamically.
- Mount the microfrontend and call the CRM confirmation endpoint only after the SSO handshake succeeds.

The SSO endpoint and mappings are implemented in isolated development branches. They have not yet passed build, replay, CORS, cross-tenant or browser end-to-end tests and must not be treated as production-ready.

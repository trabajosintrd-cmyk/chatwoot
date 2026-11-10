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

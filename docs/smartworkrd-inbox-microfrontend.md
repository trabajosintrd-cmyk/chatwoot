# Smart Work RD Inbox — Microfrontend

## Estado

Implementación aislada en la rama `smartworkrd/inbox-microfrontend-spike`, basada en Chatwoot Community 4.19.1. Está preparada para integrarse en la shell Next.js del CRM, pero **no está validada ni desplegada en producción**.

## Qué contiene el fork

- Ruta `/smartworkrd/inbox` para pruebas directas.
- Ruta `/smartworkrd/inbox/assets`, que devuelve los tags Vite de CSS y JavaScript para el loader remoto.
- Entry point Vue con ciclo `mount(element, options)` / `unmount(element)`.
- Vue Router con historial en memoria y solo las rutas de conversación.
- Montaje directo de `ConversationView`, sin sidebar, topbar, login ni selector global de cuenta de Chatwoot.
- Bridge global `window.SmartWorkRDInbox`.
- Estilos scoped para el mount point, utilidades Tailwind y tokens de Smart Work RD.
- Paleta primaria verde bosque y tema claro; la shell CRM conserva el control del tema.
- Endpoint `POST /smartworkrd/sso/consume` para tickets firmados de un solo uso.

## Contrato visual

La shell React del CRM es la única propietaria de navegación, cabecera, selector de tenant/negocio, sesión, permisos y tema. Chatwoot ocupa exclusivamente el área funcional de conversaciones.

El microfrontend:
- Hereda la identidad clara del CRM: canvas gris, superficies blancas, texto carbón y acciones verde bosque.
- No importa el stylesheet global del dashboard Chatwoot, que cambiaría tipografía y estilos del documento anfitrión.
- Usa un root scoped con los tokens de color necesarios.
- No añade una segunda navegación ni un segundo dashboard.

## Ciclo del host

El host debe:

1. Solicitar un ticket al CRM API con el usuario Supabase autenticado y el negocio activo.
2. Enviar el ticket a `POST /smartworkrd/sso/consume`.
3. Guardar el objeto `auth` devuelto en la cookie legible por JavaScript `cw_d_session_info` del origen CRM; el token nunca viaja en la URL.
4. Definir `window.chatwootConfig.apiHost` y `hostURL` con el origen Chatwoot.
5. Obtener los tags de recursos en `/smartworkrd/inbox/assets`, cargar CSS y entrypoint Vite, y llamar `window.SmartWorkRDInbox.mount(container, { accountId })`.
6. Llamar al endpoint CRM `confirm` solo después de que el montaje SSO haya tenido éxito.
7. Llamar `unmount()` al desmontar el módulo.

El repositorio CRM ya contiene el componente `ChatwootInboxMount` que realiza este flujo y reemplaza la bandeja anterior en la misma ruta cuando `NEXT_PUBLIC_CHATWOOT_INBOX_ENABLED=true`. El flag permanece en `false` por defecto. No aparecen dos bandejas simultáneamente.

## SSO y autorización

El endpoint Chatwoot valida:
- Firma HS256, issuer, audience, expiración y origen permitido.
- Ticket con `jti` único y no reutilizado.
- Rol CRM permitido: owner, admin, supervisor o agent.
- Usuario Chatwoot activo, miembro de la cuenta indicada y con rol compatible.

Al consumirlo, Chatwoot crea una credencial Devise Token Auth y devuelve los headers en una respuesta JSON `no-store`. La tabla `smart_work_rd_sso_tickets` registra el `jti` consumido y bloquea replays.

El CRM mantiene los vínculos tenant-scoped entre tenant, cuenta Chatwoot y usuario externo. Cambiar la cuenta elimina los vínculos de usuario anteriores para evitar reutilizar identidades de otra cuenta. La UI de Integraciones permite configurar la cuenta y el usuario actual; el resto de los miembros debe vincularse individualmente antes de acceder.

## Variables de entorno

En la API CRM:
- `CHATWOOT_SSO_SECRET`: secreto aleatorio de al menos 32 bytes.
- `CHATWOOT_SSO_ISSUER=smartworkrd-crm`.
- `CHATWOOT_SSO_AUDIENCE=chatwoot`.

En Chatwoot:
- `SMARTWORKRD_SSO_SECRET`: el mismo secreto que la API CRM.
- `SMARTWORKRD_SSO_ISSUER=smartworkrd-crm`.
- `SMARTWORKRD_SSO_AUDIENCE=chatwoot`.
- `SMARTWORKRD_ALLOWED_ORIGIN`: origen exacto del CRM, sin slash final.
- `ENABLE_API_CORS=true`.
- `FORCE_SSL=true` en producción.

CORS de assets permite cargar Vite desde el host; CORS de API y Action Cable queda limitado al origen CRM configurado. No se usa cookie compartida entre subdominios: el host guarda la credencial Chatwoot en su propio origen para que el entrypoint pueda leerla y añadir headers a las solicitudes API.

## Pendiente antes de producción

- Build, lint y pruebas de migración en una base real.
- Validación real de create_new_auth_token, cookie, API CORS y Action Cable.
- Smoke test de lista, abrir conversación, enviar mensaje, notas, archivos, realtime y desmontaje.
- Prueba de replay, ticket expirado, origen no autorizado y roles incompatibles.
- Prueba de aislamiento con dos tenants y dos cuentas Chatwoot.
- CSP y dominios finales del despliegue.
- Provisionamiento automatizado de cuentas/usuarios y pantalla de mapeo para todos los miembros.
- Verificación visual y responsive en staging.

No conectar tráfico real ni activar el feature flag hasta superar esas pruebas.

## Prueba local directa

1. Inicia Chatwoot con sus instrucciones habituales.
2. Inicia sesión en el mismo origen Chatwoot.
3. Abre `/smartworkrd/inbox` con un `?account_id=123` que pertenezca al usuario.
4. Comprueba cola, apertura de conversación, envío y realtime.
5. Desmonta mediante `window.SmartWorkRDInbox.unmount()`.

La prueba directa usa la cookie `cw_d_session_info` existente. La prueba integrada debe usar el flujo SSO descrito arriba.

## Licencia

Este spike importa únicamente código Community. Mantén los avisos MIT y de terceros. No importes código de `enterprise/` ni archivos marcados Enterprise sin una licencia escrita independiente.

import { createApp } from 'vue';
import { createMemoryHistory, createRouter } from 'vue-router';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import hljsVuePlugin from '@highlightjs/vue-plugin';
import { plugin, defaultConfig } from '@formkit/vue';
import FloatingVue from 'floating-vue';
import { createPinia } from 'pinia';
import { sync } from 'vuex-router-sync';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { vResizeObserver } from '@vueuse/components';
import { directive as onClickaway } from 'vue3-click-away';

import WootWizard from 'components/ui/Wizard.vue';
import WootUiKit from 'dashboard/components';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon.vue';
import i18nMessages from 'dashboard/i18n';
import createAxios from 'dashboard/helper/APIHelper';
import commonHelpers, { isJSONValid } from 'dashboard/helper/commons';
import constants from 'dashboard/constants/globals';
import store from 'dashboard/store';
import conversationRoutes from 'dashboard/routes/dashboard/conversation/conversation.routes';
import {
  getCurrentAccount,
  getUserPermissions,
} from 'dashboard/helper/permissionsHelper';
import { routeIsAccessibleFor } from 'dashboard/helper/routeHelpers';
import vueActionCable from 'dashboard/helper/actionCable';
import ReconnectService from 'dashboard/helper/ReconnectService';
import {
  initializeAnalyticsEvents,
  initializeChatwootEvents,
} from 'dashboard/helper/scriptHelpers.js';
import { domPurifyConfig } from 'shared/helpers/HTMLSanitizer';
import SmartWorkInbox from '../smartworkrd/SmartWorkInbox.vue';

import 'floating-vue/dist/style.css';
import '../smartworkrd/inbox.scss';
import '@chatwoot/viz/style.css';

let globalHelpersInitialized = false;
let activeInstance = null;
let mounting = false;

const initializeGlobalHelpers = () => {
  if (!globalHelpersInitialized) {
    commonHelpers();
    initializeChatwootEvents();
    initializeAnalyticsEvents();
    globalHelpersInitialized = true;
  }

  window.WootConstants = constants;
  window.axios = createAxios(axios);
};

const getRequestedAccountId = (options, user) => {
  const queryAccountId = new URLSearchParams(window.location.search).get(
    'account_id'
  );
  const accountId = Number(
    options.accountId ||
      queryAccountId ||
      user.account_id ||
      user.accounts?.[0]?.id
  );

  if (!Number.isSafeInteger(accountId) || accountId <= 0) {
    throw new Error(
      'No encontramos una cuenta de Chatwoot válida para abrir la bandeja.'
    );
  }

  return accountId;
};

const createInboxRouter = () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: conversationRoutes.routes,
  });

  router.beforeEach(to => {
    const user = store.getters.getCurrentUser;
    const accountId = Number(to.params.accountId);
    const account = getCurrentAccount(user, accountId);

    if (!account || (account.status && account.status !== 'active')) {
      return false;
    }

    const permissions = getUserPermissions(user, accountId);
    return routeIsAccessibleFor(to, permissions);
  });

  return router;
};

const installPlugins = (app, router, element, locale) => {
  const i18n = createI18n({
    legacy: false,
    locale: locale || 'en',
    fallbackLocale: 'en',
    messages: i18nMessages,
  });

  app.use(i18n);
  app.use(store);
  app.use(createPinia());
  app.use(router);
  app.use(VueDOMPurifyHTML, domPurifyConfig);
  app.use(WootUiKit);
  app.use(
    plugin,
    defaultConfig({
      rules: {
        JSON: ({ value }) => isJSONValid(value),
      },
    })
  );
  app.use(FloatingVue, {
    instantMove: true,
    arrowOverflow: false,
    disposeTimeout: 5000000,
    container: element,
    themes: {
      tooltip: {
        strategy: 'fixed',
      },
    },
  });
  app.use(hljsVuePlugin);

  app.component('woot-wizard', WootWizard);
  app.component('fluent-icon', FluentIcon);
  app.directive('resize', vResizeObserver);
  app.directive('on-clickaway', onClickaway);
};

export const unmountSmartWorkInbox = element => {
  if (!activeInstance || (element && element !== activeInstance.element)) {
    return false;
  }

  activeInstance.reconnectService?.disconnect();
  activeInstance.actionCable?.disconnect();
  activeInstance.app.unmount();
  activeInstance.unsync?.();
  store.dispatch('clearSelectedState');

  if (window.reconnectService === activeInstance.reconnectService) {
    delete window.reconnectService;
  }

  activeInstance = null;
  return true;
};

export const mountSmartWorkInbox = async (element, options = {}) => {
  if (!(element instanceof HTMLElement)) {
    throw new Error(
      'Debes indicar el contenedor donde se mostrará la bandeja.'
    );
  }

  if (activeInstance) {
    if (activeInstance.element === element) {
      return activeInstance.handle;
    }
    throw new Error(
      'La bandeja Smart Work RD ya está montada en otro contenedor.'
    );
  }

  if (mounting) {
    throw new Error('La bandeja Smart Work RD se está inicializando.');
  }

  mounting = true;
  let app;
  let unsync;
  let actionCable;
  let reconnectService;

  try {
    initializeGlobalHelpers();
    await store.dispatch('setUser');

    const user = store.getters.getCurrentUser;
    if (!store.getters.isLoggedIn || !user?.accounts?.length) {
      throw new Error(
        'Inicia sesión en Chatwoot antes de abrir la bandeja.'
      );
    }

    const accountId = getRequestedAccountId(options, user);
    const accountMembership = getCurrentAccount(user, accountId);
    if (!accountMembership) {
      throw new Error(
        'Tu usuario no tiene acceso a la cuenta de Chatwoot solicitada.'
      );
    }

    await store.dispatch('accounts/get', { accountId });
    await store.dispatch('setActiveAccount', { accountId });

    const account = store.getters['accounts/getAccount'](accountId);
    if (!account?.id) {
      throw new Error('No pudimos cargar la cuenta de Chatwoot seleccionada.');
    }

    const router = createInboxRouter();
    unsync = sync(store, router);

    const navigation = await router.push(
      `/app/accounts/${accountId}/dashboard`
    );
    await router.isReady();

    if (navigation?.type || router.currentRoute.value.name !== 'home') {
      throw new Error(
        'No pudimos abrir la bandeja con los permisos de esta cuenta.'
      );
    }

    app = createApp(SmartWorkInbox);
    installPlugins(
      app,
      router,
      element,
      user.ui_settings?.locale || account.locale
    );

    // The CRM host owns the theme. The scoped inbox root carries the light palette;
    // do not mutate body or document-level theme state.
    app.mount(element);

    if (user.pubsub_token) {
      actionCable = vueActionCable.init(store, user.pubsub_token);
      reconnectService = new ReconnectService(store, router);
      window.reconnectService = reconnectService;
    }

    const handle = {
      unmount: () => unmountSmartWorkInbox(element),
    };

    activeInstance = {
      element,
      app,
      unsync,
      actionCable,
      reconnectService,
      handle,
    };

    return handle;
  } catch (error) {
    reconnectService?.disconnect();
    actionCable?.disconnect();
    app?.unmount();
    unsync?.();
    throw error;
  } finally {
    mounting = false;
  }
};

if (typeof window !== 'undefined') {
  window.SmartWorkRDInbox = {
    mount: mountSmartWorkInbox,
    unmount: unmountSmartWorkInbox,
  };

  const standaloneRoot = document.querySelector('[data-smartworkrd-inbox]');
  if (standaloneRoot) {
    mountSmartWorkInbox(standaloneRoot).catch(error => {
      standaloneRoot.replaceChildren();
      const message = document.createElement('p');
      message.setAttribute('role', 'alert');
      message.className = 'p-6 text-sm text-n-slate-12';
      message.textContent =
        error instanceof Error
          ? error.message
          : 'No se pudo inicializar la bandeja.';
      standaloneRoot.append(message);
    });
  }
}

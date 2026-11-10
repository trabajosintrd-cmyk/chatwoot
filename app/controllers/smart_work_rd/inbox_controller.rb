module SmartWorkRd
  class InboxController < DashboardController
    skip_before_action :ensure_html_format, only: :config

    def assets
      response.headers['Cache-Control'] = 'public, max-age=300'
      render layout: false
    end

    def config
      response.headers['Cache-Control'] = 'private, no-store'
      response.headers['Pragma'] = 'no-cache'

      chatwoot_config = {
        hostURL: ENV.fetch('FRONTEND_URL', ''),
        helpCenterURL: ENV.fetch('HELPCENTER_URL', ''),
        fbAppId: @global_config['FB_APP_ID'],
        instagramAppId: @global_config['INSTAGRAM_APP_ID'],
        tiktokAppId: @global_config['TIKTOK_APP_ID'],
        googleOAuthClientId: ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil),
        googleOAuthCallbackUrl: ENV.fetch('GOOGLE_OAUTH_CALLBACK_URL', nil),
        allowedLoginMethods: @global_config['ALLOWED_LOGIN_METHODS'],
        fbApiVersion: @global_config['FACEBOOK_API_VERSION'],
        whatsappAppId: @global_config['WHATSAPP_APP_ID'],
        whatsappConfigurationId: @global_config['WHATSAPP_CONFIGURATION_ID'],
        whatsappApiVersion: @global_config['WHATSAPP_API_VERSION'],
        signupEnabled: @global_config['ENABLE_ACCOUNT_SIGNUP'],
        isEnterprise: @global_config['IS_ENTERPRISE'],
        isMfaEnabled: Chatwoot.mfa_enabled?,
        enabledLanguages: helpers.available_locales_with_name,
        helpUrls: helpers.feature_help_urls,
        inboxEventsEnabled: ENV['ENABLE_INBOX_EVENTS'].present?,
        searchTimeRangeLimitDays: Limits.search_time_range_limit_days,
        autoResolveMinMinutes: Limits.auto_resolve_min_minutes,
        selectedLocale: I18n.locale
      }

      vapid_key = @global_config['VAPID_PUBLIC_KEY']
      chatwoot_config[:vapidPublicKey] = Base64.urlsafe_decode64(vapid_key).bytes if vapid_key.present?

      render json: {
        chatwootConfig: chatwoot_config,
        globalConfig: @global_config,
        browserConfig: {}
      }
    end

    private

    def set_application_pack
      @application_pack = 'smartworkrd-inbox'
    end
  end
end

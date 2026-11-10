# CORS for the public Chatwoot assets and Smart Work RD host integration.
smartworkrd_origin = ENV.fetch('SMARTWORKRD_ALLOWED_ORIGIN', '').strip

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    resource '/packs/*', headers: :any, methods: [:get, :options]
    resource '/vite/*', headers: :any, methods: [:get, :options]
    resource '/audio/*', headers: :any, methods: [:get, :options]
    resource '/public/api/*', headers: :any, methods: :any
  end

  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_API_CORS', false))
    if smartworkrd_origin.present?
      allow do
        origins smartworkrd_origin
        resource '/api/*',
                 headers: :any,
                 methods: :any,
                 expose: %w[access-token client uid expiry]
      end
    else
      allow do
        origins '*'
        resource '/api/*',
                 headers: :any,
                 methods: :any,
                 expose: %w[access-token client uid expiry]
      end
    end
  end

  if smartworkrd_origin.present?
    allow do
      origins smartworkrd_origin
      resource '/smartworkrd/sso/consume',
               headers: :any,
               methods: [:post, :options]
    end

    Rails.application.config.action_cable.allowed_request_origins = [smartworkrd_origin]
  end
end

################################################
######### Action Cable Related Config ##########
################################################

# Mount Action Cable outside main process or domain
# Rails.application.config.action_cable.mount_path = nil
# Rails.application.config.action_cable.url = 'wss://example.com/cable'

# Action Cable is enabled for the Smart Work RD host only when its origin is configured.
Rails.application.config.action_cable.disable_request_forgery_protection = false

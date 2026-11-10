module SmartWorkRd
  class SsoController < ApplicationController
    class SsoForbiddenError < StandardError; end
    class SsoConfigurationError < StandardError; end

    skip_before_action :set_current_user
    before_action :set_no_store_headers
    before_action :verify_smartworkrd_origin!

    def consume
      claims = validated_ticket_claims(decode_ticket(params.require(:ticket)))
      account, user = resolve_chatwoot_identity(claims)
      auth_headers = consume_ticket(claims, account, user)

      render json: {
        auth: auth_headers,
        account_id: account.id,
        user_id: user.id,
        expires_at: Time.at(auth_headers.fetch('expiry').to_i).utc.iso8601
      }, status: :ok
    rescue SsoConfigurationError
      render json: { error: 'La autenticación SSO no está configurada en Chatwoot.' }, status: :service_unavailable
    rescue SsoForbiddenError
      render json: { error: 'El usuario no tiene permisos para esta cuenta de Chatwoot.' }, status: :forbidden
    rescue JWT::DecodeError, KeyError, ArgumentError, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      render json: { error: 'El ticket SSO no es válido, ya fue utilizado o ha expirado.' }, status: :unauthorized
    end

    private

    def decode_ticket(ticket)
      secret = ENV['SMARTWORKRD_SSO_SECRET'].to_s
      raise SsoConfigurationError if secret.bytesize < 32

      issuer = ENV.fetch('SMARTWORKRD_SSO_ISSUER', 'smartworkrd-crm')
      audience = ENV.fetch('SMARTWORKRD_SSO_AUDIENCE', 'chatwoot')

      JWT.decode(
        ticket,
        secret,
        true,
        algorithm: 'HS256',
        iss: issuer,
        verify_iss: true,
        aud: audience,
        verify_aud: true,
        verify_expiration: true
      ).first
    end

    def validated_ticket_claims(claims)
      data = {
        crm_user_id: claims.fetch('sub').to_s,
        tenant_id: claims.fetch('tenant_id').to_s,
        business_id: claims.fetch('business_id').to_s,
        account_id: Integer(claims.fetch('chatwoot_account_id').to_s, 10),
        user_id: Integer(claims.fetch('chatwoot_user_id').to_s, 10),
        crm_role: claims.fetch('crm_role').to_s,
        jti: claims.fetch('jti').to_s,
        issued_at: Integer(claims.fetch('iat')),
        expires_at: Time.at(Integer(claims.fetch('exp')))
      }

      uuid_pattern = /\A[0-9a-f-]{36}\z/i
      valid_ids = %i[crm_user_id tenant_id business_id jti].all? do |key|
        data.fetch(key).match?(uuid_pattern)
      end
      valid_time = data[:issued_at] <= 5.seconds.from_now.to_i &&
                   data[:expires_at] > Time.current &&
                   data[:expires_at] <= 90.seconds.from_now &&
                   data[:expires_at].to_i - data[:issued_at] <= 90

      raise JWT::DecodeError, 'Invalid SSO ticket claims' unless valid_ids && valid_time
      raise SsoForbiddenError unless %w[owner admin supervisor agent].include?(data[:crm_role])

      data
    end

    def resolve_chatwoot_identity(claims)
      account = Account.find_by(id: claims.fetch(:account_id))
      user = User.find_by(id: claims.fetch(:user_id))
      account_user = AccountUser.find_by(
        account_id: claims.fetch(:account_id),
        user_id: claims.fetch(:user_id)
      )
      expected_role = %w[owner admin].include?(claims.fetch(:crm_role)) ? 'administrator' : 'agent'

      unless account&.active? && user&.active_for_authentication? &&
             account_user&.role == expected_role
        raise SsoForbiddenError
      end

      [account, user]
    end

    def consume_ticket(claims, account, user)
      auth_headers = nil

      SmartWorkRd::SsoTicket.transaction do
        SmartWorkRd::SsoTicket.where('expires_at < ?', 1.day.ago).delete_all
        SmartWorkRd::SsoTicket.create!(
          jti: claims.fetch(:jti),
          tenant_id: claims.fetch(:tenant_id),
          business_id: claims.fetch(:business_id),
          account_id: account.id,
          user_id: user.id,
          crm_role: claims.fetch(:crm_role),
          expires_at: claims.fetch(:expires_at),
          consumed_at: Time.current
        )
        auth_headers = user.create_new_auth_token
      end

      auth_headers
    end

    def set_no_store_headers
      response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
    end

    def verify_smartworkrd_origin!
      configured_origin = ENV['SMARTWORKRD_ALLOWED_ORIGIN'].to_s.strip.sub(%r{/\z}, '')
      request_origin = request.headers['Origin'].to_s.strip.sub(%r{/\z}, '')

      return if configured_origin.present? && request_origin == configured_origin

      render json: { error: 'Origen no autorizado.' }, status: :forbidden
    end
  end
end

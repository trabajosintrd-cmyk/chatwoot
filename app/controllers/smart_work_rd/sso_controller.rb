module SmartWorkRd
  class SsoController < ApplicationController
    skip_before_action :set_current_user
    before_action :verify_smartworkrd_origin!

    def consume
      ticket = params.require(:ticket)
      claims = decode_ticket(ticket)

      crm_user_id = claims.fetch('sub').to_s
      tenant_id = claims.fetch('tenant_id').to_s
      business_id = claims.fetch('business_id').to_s
      account_id = Integer(claims.fetch('chatwoot_account_id').to_s, 10)
      user_id = Integer(claims.fetch('chatwoot_user_id').to_s, 10)
      crm_role = claims.fetch('crm_role').to_s
      jti = claims.fetch('jti').to_s
      expires_at = Time.at(Integer(claims.fetch('exp')))

      unless crm_user_id.match?(/\A[0-9a-f-]{36}\z/i) &&
             tenant_id.match?(/\A[0-9a-f-]{36}\z/i) &&
             business_id.match?(/\A[0-9a-f-]{36}\z/i) &&
             jti.match?(/\A[0-9a-f-]{36}\z/i) &&
             expires_at > Time.current &&
             expires_at <= 90.seconds.from_now
        return render json: { error: 'El ticket SSO no es válido o ha expirado.' }, status: :unauthorized
      end

      unless %w[owner admin supervisor agent].include?(crm_role)
        return render json: { error: 'El rol del CRM no tiene acceso a la bandeja.' }, status: :forbidden
      end

      account = Account.find_by(id: account_id)
      user = User.find_by(id: user_id)
      account_user = AccountUser.find_by(account_id: account_id, user_id: user_id)
      expected_chatwoot_role = %w[owner admin].include?(crm_role) ? 'administrator' : 'agent'

      unless account && user&.active_for_authentication? &&
             account_user&.role == expected_chatwoot_role
        return render json: { error: 'La identidad no tiene acceso a la cuenta de Chatwoot indicada.' }, status: :forbidden
      end

      auth_headers = nil

      SmartWorkRd::SsoTicket.transaction do
        SmartWorkRd::SsoTicket.where('expires_at < ?', 1.day.ago).delete_all
        SmartWorkRd::SsoTicket.create!(
          jti: jti,
          tenant_id: tenant_id,
          business_id: business_id,
          account_id: account_id,
          user_id: user_id,
          crm_role: crm_role,
          expires_at: expires_at,
          consumed_at: Time.current
        )
        auth_headers = user.create_new_auth_token
      end

      response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
      response.headers['Pragma'] = 'no-cache'

      render json: {
        auth: auth_headers,
        account_id: account.id,
        user_id: user.id,
        expires_at: Time.at(auth_headers.fetch('expiry').to_i).utc.iso8601
      }, status: :ok
    rescue JWT::DecodeError, KeyError, ArgumentError, ActiveRecord::RecordNotUnique
      render json: { error: 'El ticket SSO no es válido, ya fue utilizado o ha expirado.' }, status: :unauthorized
    end

    private

    def decode_ticket(ticket)
      secret = ENV['SMARTWORKRD_SSO_SECRET'].to_s
      raise JWT::DecodeError, 'SSO secret is not configured' if secret.bytesize < 32

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

    def verify_smartworkrd_origin!
      configured_origin = ENV['SMARTWORKRD_ALLOWED_ORIGIN'].to_s.strip.sub(%r{/\z}, '')
      request_origin = request.headers['Origin'].to_s.strip.sub(%r{/\z}, '')

      return if configured_origin.present? && request_origin == configured_origin

      render json: { error: 'Origen no autorizado.' }, status: :forbidden
    end
  end
end

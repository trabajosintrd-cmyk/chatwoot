require 'rails_helper'

RSpec.describe 'Smart Work RD SSO', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:origin) { 'https://crm.smartworkrd.com' }
  let(:secret) { 'smart-work-rd-test-secret-that-is-at-least-32-bytes' }

  around do |example|
    keys = %w[
      SMARTWORKRD_SSO_SECRET
      SMARTWORKRD_SSO_ISSUER
      SMARTWORKRD_SSO_AUDIENCE
      SMARTWORKRD_ALLOWED_ORIGIN
    ]
    previous = keys.to_h { |key| [key, ENV[key]] }

    ENV['SMARTWORKRD_SSO_SECRET'] = secret
    ENV['SMARTWORKRD_SSO_ISSUER'] = 'smartworkrd-crm'
    ENV['SMARTWORKRD_SSO_AUDIENCE'] = 'chatwoot'
    ENV['SMARTWORKRD_ALLOWED_ORIGIN'] = origin

    example.run
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def build_ticket(user:, account:, crm_role: 'agent', jti: SecureRandom.uuid, expires_at: 60.seconds.from_now.to_i)
    now = Time.current.to_i
    JWT.encode(
      {
        sub: SecureRandom.uuid,
        tenant_id: SecureRandom.uuid,
        business_id: SecureRandom.uuid,
        chatwoot_account_id: account.id,
        chatwoot_user_id: user.id,
        crm_role: crm_role,
        jti: jti,
        iat: now,
        exp: expires_at,
        iss: 'smartworkrd-crm',
        aud: 'chatwoot'
      },
      secret,
      'HS256'
    )
  end

  def consume(ticket, request_origin: origin)
    post '/smartworkrd/sso/consume',
         params: { ticket: ticket },
         headers: { 'Origin' => request_origin },
         as: :json
  end

  describe 'POST /smartworkrd/sso/consume' do
    it 'exchanges a valid one-time ticket for Chatwoot auth headers' do
      consume(build_ticket(user: agent, account: account))

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')

      body = response.parsed_body
      expect(body['account_id']).to eq(account.id)
      expect(body['user_id']).to eq(agent.id)
      expect(body['auth']).to include(
        'access-token',
        'token-type',
        'client',
        'expiry',
        'uid'
      )
    end

    it 'rejects replaying a consumed ticket' do
      ticket = build_ticket(user: agent, account: account)

      consume(ticket)
      expect(response).to have_http_status(:ok)

      consume(ticket)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects requests from an origin other than the configured CRM' do
      consume(
        build_ticket(user: agent, account: account),
        request_origin: 'https://untrusted.example'
      )

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects an expired ticket' do
      consume(
        build_ticket(
          user: agent,
          account: account,
          expires_at: 1.minute.ago.to_i
        )
      )

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a CRM administrator mapped to a Chatwoot agent account' do
      consume(
        build_ticket(
          user: agent,
          account: account,
          crm_role: 'admin'
        )
      )

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /smartworkrd/inbox' do
    it 'renders the standalone mount point used for direct smoke tests' do
      get '/smartworkrd/inbox', params: { account_id: account.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-smartworkrd-inbox')
    end
  end
end

module SmartWorkRd
  class SsoTicket < ApplicationRecord
    validates :jti, presence: true, uniqueness: true
    validates :tenant_id, :business_id, :crm_role, :expires_at, :consumed_at, presence: true
  end
end

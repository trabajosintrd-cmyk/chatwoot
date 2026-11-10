class CreateSmartWorkRdSsoTickets < ActiveRecord::Migration[7.0]
  def change
    create_table :smart_work_rd_sso_tickets do |t|
      t.string :jti, null: false
      t.uuid :tenant_id, null: false
      t.uuid :business_id, null: false
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :crm_role, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at, null: false

      t.timestamps
    end

    add_index :smart_work_rd_sso_tickets, :jti, unique: true
    add_index :smart_work_rd_sso_tickets, :expires_at
    add_foreign_key :smart_work_rd_sso_tickets, :accounts, on_delete: :cascade
    add_foreign_key :smart_work_rd_sso_tickets, :users, on_delete: :cascade
  end
end

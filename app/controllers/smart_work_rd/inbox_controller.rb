module SmartWorkRd
  class InboxController < DashboardController
    def assets
      response.headers['Cache-Control'] = 'public, max-age=300'
      render layout: false
    end

    private

    def set_application_pack
      @application_pack = 'smartworkrd-inbox'
    end
  end
end

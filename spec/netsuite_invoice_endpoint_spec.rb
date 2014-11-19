require 'spec_helper'

describe NetsuiteEndpoint do

  include_examples 'request parameters'

  describe 'invoices' do
    context 'when order is new' do

      let(:request) do

        # Not in Spree so add our location ID to the config parameters
        parameters[:netsuite_location_internalid] = 4

        # loads from support/payload/<xyz>_payload.json
        payload = Factories.invoice_order_with_subscription_payload.merge(parameters: parameters )
        payload
      end

      it 'imports the invoice and returns an info notification' do
        VCR.use_cassette('invoice/import_service', :record => :all, :allow_playback_repeats => true) do
          post '/add_invoice', request.to_json, auth
          expect(last_response).to be_ok
        end

        expect(json_response[:summary]).to include('Invoice successfully created in NetSuite for Order')
      end
    end
  end

end

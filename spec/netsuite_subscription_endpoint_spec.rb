require 'spec_helper'

describe NetsuiteEndpoint do

  include_examples 'request parameters'

  #TODO create a shared example to create the invoice we can link to

  describe 'subscriptions' do

    context 'new shipment each month' do

      let(:invoice_number) { 'RENDPOINT0002' }

      let(:request) do
        # loads from support/payload/<xyz>_payload.json
        payload = Factories.shipment_with_subscription_payload.merge(parameters: parameters )

        payload['shipments']['order_id'] = invoice_number

        payload
      end

      it 'imports the shipment as SalesOrder and returns an info notification' do
        VCR.use_cassette('subscription/import_shipment') do
          post '/add_subscription', request.to_json, auth
          expect(last_response).to be_ok
        end

        expect(json_response[:summary]).to include('created for Subscription in NetSuite')
      end
    end
  end

end

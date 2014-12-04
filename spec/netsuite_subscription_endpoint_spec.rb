require 'spec_helper'

describe NetsuiteEndpoint do

  include_examples 'request parameters'

  let(:message_500){  "Failed to create NetSuite SalesOrder -" }
  let(:message_200){  "Successfully created NetSuite Sales Order" }

  describe 'subscriptions' do

    context 'new shipment each month' do

      let(:invoice_number) { "RSPEC_SHIP_#{Time.now.hour}#{Time.now.min}" }

      let(:invoice_request) do
        # Not in Spree so add our location ID to the config parameters
        parameters[:netsuite_location_internalid] = 4

        parameters[:netsuite_save_ref_in_memo] = true

        # loads from support/payload/<xyz>_payload.json
        payload = Factories.invoice_order_with_subscription_payload.merge(parameters: parameters )

        payload['order']['number'] = invoice_number
        payload
      end

      let(:shipment_request) do
        # loads from support/payload/<xyz>_payload.json
        payload = Factories.subscription_unit_payload.merge(parameters: parameters )

        shipment_payload =  payload['shipments'] ? payload['shipments'][0]: payload['shipment']
        shipment_payload['order_number'] = invoice_number

        payload
      end

      it 'imports the shipment as SalesOrder and returns an info notification' do
        VCR.use_cassette('subscription/import_shipment', :record => :all, :allow_playback_repeats => true) do

          post '/add_invoice', invoice_request.to_json, auth  # invoice against which SO needs to link

          post '/add_subscription', shipment_request.to_json, auth
          expect(last_response).to be_ok
          expect(json_response[:summary]).to include(message_200)
        end
      end

    end
  end

end

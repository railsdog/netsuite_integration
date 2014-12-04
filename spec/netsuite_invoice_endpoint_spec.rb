require 'spec_helper'

describe NetsuiteEndpoint do

  include_examples 'request parameters'


  describe 'invoices' do

    let(:message_500){  "Failed to create NetSuite Invoice " }
    let(:message_200){  "Successfully created NetSuite Invoice for Order" }

    let(:invoice_number) { 'RENDPOINT0004' }

    let(:request) do

      # Not in Spree so add our location ID to the config parameters
      parameters[:netsuite_location_internalid] = 4

      parameters[:netsuite_save_ref_in_memo] = true

      # loads from support/payload/<xyz>_payload.json
      payload = Factories.invoice_order_with_subscription_payload.merge(parameters: parameters )

      payload['order']['number'] = invoice_number

      payload
    end


    context 'when order is new' do

      it 'imports the invoice and returns an info notification' do
        VCR.use_cassette('invoice/import_service') do
          post '/add_invoice', request.to_json, auth
          expect(last_response).to be_ok
          expect(json_response[:summary]).to include(message_200)
        end
      end

      it 'rejects the order when invoice already exists' do
        VCR.use_cassette('invoice/import_service_again') do
          post '/add_invoice', request.to_json, auth
          expect(last_response.status).to eq 500
          expect(json_response[:summary]).to include(message_500)
          expect(json_response[:summary]).to include( "NetSuite Invoice already raised")

        end
      end
    end

    context "item not found" do
      before {

        request['order']['line_items'][0]['name'] = "Im not there"
        request['order']['line_items'][0]['sku'] = "Im not there"

        request['order']['number'] = "RDOESNOTEXIST_XXX"
      }

      it "returns 500 and gives no stock:actual message", :fail => true do
        VCR.use_cassette("invoice/item_not_found", :record => :all, :allow_playback_repeats => true) do
          post '/add_invoice', request.to_json, auth

          expect(last_response.status).to eq 500
          expect(json_response[:summary]).to include(message_500)
          expect(json_response[:summary]).to include("Non Inventory Item [Im not there] not found in NetSuite")
        end
      end
    end

    context 'unhandled error' do
      it 'returns 500 and a notification' do
        NetSuite::Records::Invoice.should_receive(:new).and_raise 'Weird error'

        post '/add_invoice', request.to_json, auth
        expect(last_response.status).to eq 500
        expect(json_response[:summary]).to match "Weird error"
      end
    end


  end

end

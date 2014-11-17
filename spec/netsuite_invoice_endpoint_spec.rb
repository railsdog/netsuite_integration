require 'spec_helper'

describe NetsuiteEndpoint do

  include_examples 'request parameters'

  let(:request) do
    { parameters: parameters }
  end


  describe 'invoices' do
    context 'when order is new' do

      let(:request) do
        # loads from support/payload/<xyz>_payload.json
        payload = Factories.order_with_subscription_payload.merge(parameters: parameters)
        payload['order']['number'] = "RXXXXXC23774"
        payload
      end

      it 'imports the invoice and returns an info notification' do
        VCR.use_cassette('invoice/import_service', :record => :all, :allow_playback_repeats => true) do
          puts "#TS CALLING add_invoice : #{request.inspect}\n#{auth}\n"
          post '/add_invoice', request.to_json, auth
          expect(last_response).to be_ok
        end

        expect(json_response[:summary]).to match('sent to NetSuite')
      end
    end
  end

end

require 'spec_helper'

module NetsuiteIntegration

  describe Subscription do

    include_examples 'config hash'
    include_examples 'connect to netsuite'

    context 'monthly shipment' do

      let(:invoice_number) { 'RREGR4354ABHI' }

      subject do
        payload = Factories.subscription_unit_payload

        shipment_payload =  payload['shipments'] ? payload['shipments'][0]: payload['shipment']
        shipment_payload['order_number'] = invoice_number

        # Not in Spree so add our location ID to the config parameters
        config[:netsuite_location_internalid] = 4

        described_class.new(config, payload)
      end

      it 'can find the assembly unit' do
        VCR.use_cassette('subscription/subscription_lookup', :record => :all, :allow_playback_repeats => true) do
          subject.shipment_payload[:items].each do |item|
            expect(subject.find_item(item)).to be
          end
        end
      end

    end

  end
end

require 'spec_helper'

module NetsuiteIntegration

  describe Invoice do

    include_examples 'config hash'
    include_examples 'connect to netsuite'

    context 'customers' do

      let(:payload) { Factories.invoice_order_with_subscription_payload }

      subject do
        # Not in Spree so add our location ID to the config parameters
        config[:netsuite_location_internalid] = 4

        payload[:email] = "spree@example.com"

        described_class.new(config, payload)
      end


      it 'finds a customer' do
        VCR.use_cassette('invoice/find_customer', :record => :all, :allow_playback_repeats => true) do
          customer = subject.customer_service.find_by_external_id(payload[:email])
          expect(customer).to be
        end
      end


      it 'can update customer address',:debug => true do
        VCR.use_cassette('invoice/find_customer', :record => :all, :allow_playback_repeats => true) do
          customer = subject.customer_service.find_by_external_id(payload[:email])

          expect(customer).to be
          expect(customer).to be_a  NetSuite::Records::Customer

          expect(customer.email).to eq payload[:email]

          #find default
          addrbook = customer.addressbook_list.addressbooks.find { |a|
            a.default_shipping == true
          }

          expect(addrbook).to be_a NetSuite::Records::CustomerAddressbook

          puts addrbook.methods.sort.inspect

          addr = addrbook.addressbook_address

          puts "DEFAULT ADDRESS #{addr.inspect}"

          # ok turn it into a payload style hash
          default_address =  {
              addr1: addr.addr1.to_s,
              zip: addr.zip.to_s,
              city: addr.city.to_s,
              state: addr.state.to_s,
              country: addr.country.to_s
              #addr_phone: addr.field(:addr_phone).to_s.gsub(/([^0-9]*)/, "")
          }

          puts default_address.inspect

          # well since we created the hash from an existing address this better reqturn true
         expect(subject.customer_service.address_exists?(customer, default_address)).to eq true

         # expect(exists).to be true


         # puts("#TS exists : [#{exists}]")

=begin
 	3 Joe Smith
123 N Broadway
Los Angeles CA 90012
United States

            {
                default_shipping: addr.default_shipping,
                addr1: addr.addr1.to_s,
                addr2: addr.addr2.to_s,
                zip: addr.zip.to_s,
                city: addr.city.to_s,
                state: addr.state.to_s,
                country: addr.country.to_s,
                phone: addr.phone.to_s.gsub(/([^0-9]*)/, "")
            }

          if !customer_service.address_exists? customer, order_payload[:shipping_address]
              puts("#TS Address Does Not Exist - call set_or_create_default_address")
              customer_service.set_or_create_default_address customer, order_payload[:shipping_address]
            end
          else
            puts("#TS Create new Customer - check Address")
            customer = customer_service.create(order_payload.dup)
          end
=end
        end
      end
    end

    context 'when order is complete' do

      let(:invoice_number) { 'RREGR4354ABHI' }

      subject do
        payload = Factories.invoice_order_with_subscription_payload
        payload['order']['number'] = invoice_number

        # Not in Spree so add our location ID to the config parameters
        config[:netsuite_location_internalid] = 4

        described_class.new(config, payload)
      end

      it 'imports the invoice' do
        VCR.use_cassette('invoice/invoice_import') do
          invoice = subject.create

          expect(invoice).to be
          expect(invoice.external_id).to eq(invoice_number)

          # 1 line item
          expect(invoice.item_list.items.count).to eq(1)

          # amount =  item[:quantity] * item[:price] (NS amounr as a String)
          expect(invoice.item_list.items[0].amount).to eq(211.98)

          # shipping costs, address
          expect(invoice.shipping_cost).to eq 0   # be_nil
          expect(invoice.transaction_ship_address.ship_addressee).to eq('Aphex Twin')

          # billing address
          expect(invoice.transaction_bill_address.bill_addressee).to eq('Aphex Twin')
        end
      end

      it "does not reprocess an existing order", :fail => true do
        VCR.use_cassette('invoice/reject_replayed_order') do
          expect { subject.create }.to raise_error(NetSuite::InitializationError)
        end
      end
    end


    context "account for both taxes and discounts in invoice[adjustments]" do

      # map Spree name to a NonInventoryItem in your account
      let(:tax)      { "Spree Taxes" }
      let(:discount) { "Spree Taxes" }

      before do
        config['netsuite_item_for_taxes'] = tax
        config['netsuite_item_for_discounts'] = discount
      end

      let(:invoice_number) { 'RTAXDIS1247' }

      subject do
        payload = Factories.invoice_order_with_tax_ship_disc_payload
        payload['order']['number'] = invoice_number

=begin
          # This processing only required if we need to create a new NonInventoryItem
          # for example if we had

          let(:discount) { "New Discounts NonInventItem" }

          #  SPECIFIC To lootcrate cos LC has a required custom field on NII

          NetSuite::Records::NonInventorySaleItem.class_eval do
            fields :shop_or_crate?
          end

          # These are required field for LC on a NonInventorySaleItem, so must be set when creating
          # a new NII i.e to hold an adjustment e.g a new NII containing a new Tax entry called "Tax Avoidance"
          payload['order'][:netsuite_non_inventory_fields] = { 'shop_or_crate?_id' => "1", :tax_schedule_id => "2"  }
=end

        # Location reqd on Invoice - Not in Spree so add location ID to config parameters

        config[:netsuite_location_internalid] = 4

        described_class.new(config, payload)
      end

      it "builds both tax and discount line" do

        VCR.use_cassette('invoice/taxes_and_discounts') do

          invoice = subject.create

          expect(invoice).to be

          expect(invoice.item_list.items[0].quantity).to eq(1)

          expect(invoice.item_list.items.count).to eq(3)

          rates = invoice.item_list.items.map(&:rate)

          expect(rates).to include(nil)
          expect(rates).to include(1.5)
          expect(rates).to include(2.2)

        end
      end
    end

  end
end

require 'spec_helper'

module NetsuiteIntegration

  describe Invoice do

    include_examples 'config hash'
    include_examples 'connect to netsuite'

    subject do
      # Not in Spree so add our location ID to the config parameters
      config[:netsuite_location_internalid] = 4
      described_class.new(config, Factories.invoice_invoice_with_subscription_payload)
    end


    context 'when order is complete' do

      let(:invoice_number) { 'RREGR4354ABCF' }

      subject do
        payload = Factories.invoice_order_with_subscription_payload
        payload['order']['number'] = invoice_number

        # Not in Spree so add our location ID to the config parameters
        config[:netsuite_location_internalid] = 4

        described_class.new(config, payload)
      end

      it 'imports the invoice' do
        VCR.use_cassette('invoice/invoice_import', :record => :all, :allow_playback_repeats => true) do
          invoice = subject.create

          expect(invoice).to be
          expect(invoice.external_id).to eq(invoice_number)

          # 1 line item
          expect(invoice.item_list.items.count).to eq(1)

          # amount =  item[:quantity] * item[:price],
          expect(invoice.item_list.items[0].amount).to eq(211.98)


          # shipping costs, address
          expect(invoice.shipping_cost).to eq(0)
          expect(invoice.transaction_ship_address.ship_addressee).to eq('Aphex Twin')

          # billing address
          expect(invoice.transaction_bill_address.bill_addressee).to eq('Aphex Twin')
        end
      end

      context "tax, discount names" do
        let(:tax) { "Tax 2345" }
        let(:discount) { "Discount 34543" }
        let(:item) { double("Item", internal_id: 1) }

        before do
          config['netsuite_item_for_taxes'] = tax
          config['netsuite_item_for_discounts'] = discount
        end

        subject do
          described_class.any_instance.stub_chain :sales_invoice_service, :find_by_external_id

          described_class.new(config, Factories.invoice_order_with_tax_ship_disc_payload)
        end

        it "finds by using proper names" do
          expect(subject.non_inventory_item_service).to receive(:find_or_create_by_name).with(tax, nil).and_return item
          subject.send :internal_id_for, "tax"

          expect(subject.non_inventory_item_service).to receive(:find_or_create_by_name).with(discount, nil).and_return item
          subject.send :internal_id_for, "discount"
        end
      end

      context "account for both taxes and discounts in invoice[adjustments]" do

        let(:invoice_number) { 'RTAXDISABCD' }

        subject do
          payload = Factories.invoice_order_with_tax_ship_disc_payload
          payload['order']['number'] = invoice_number

          # Not in Spree so add our location ID to the config parameters
          config[:netsuite_location_internalid] = 4

          described_class.new(config, payload)
        end

        it "builds both tax and discount line" do
          #NetsuiteIntegration::Services::Customer.any_instance.stub address_exists?: true

          VCR.use_cassette('invoice/taxes_and_discounts', :record => :all, :allow_playback_repeats => true) do
            expect(subject.create).to be

            invoice.item_list.items.each {|i| puts i.inspect }

            expect(invoice.item_list.items.count).to eq(4)

            rates = subject.sales_invoice.item_list.items.map(&:rate)
            expect(rates).to include(-5)
            expect(rates).to include(25)
          end
        end
      end

=begin
    end

    context "extra attributes" do
      subject do
        payload = Factories.invoice_new_payload
        payload[:invoice][:netsuite_invoice_fields] = { department_id: 1, message: "hey you!", class_id: 1 }

        described_class.any_instance.stub_chain :sales_invoice_service, find_by_external_id: nil
        described_class.new(config, payload)
      end

      it "handles extra attributes on create" do
        expect(subject).to receive :set_up_customer
        expect(subject).to receive :build_item_list

        expect(subject).to receive :handle_extra_fields

        expect(subject.sales_invoice).to receive :add
        subject.create
      end

      it "handles extra attributes on update" do
        expect(subject).to receive :set_up_customer
        expect(subject).to receive :build_item_list

        expected = hash_including(department: instance_of(NetSuite::Records::RecordRef), message: "hey you!")
        expect(subject.sales_invoice).to receive(:update).with expected

        subject.update
      end

      it "calls setter on netsuite sales invoice record" do
        subject.handle_extra_fields
        expect(subject.sales_invoice.message).to eq "hey you!"
      end

      it "handles reserved class attribute properly" do
        subject.handle_extra_fields
        expect(subject.sales_invoice.klass.internal_id).to eq 1
      end

      it "converts them to reference when needed" do
        subject.handle_extra_fields
        expect(subject.sales_invoice.department.internal_id).to eq 1
      end
    end

    context "tax, discount names" do
      let(:tax) { "Tax 2345" }
      let(:discount) { "Discount 34543" }
      let(:item) { double("Item", internal_id: 1) }

      before do
        config['netsuite_item_for_taxes'] = tax
        config['netsuite_item_for_discounts'] = discount
      end

      subject do
        described_class.any_instance.stub_chain :sales_invoice_service, :find_by_external_id
        described_class.new(config, invoice: Factories.invoice_new_payload)
      end

      it "finds by using proper names" do
        expect(subject.non_inventory_item_service).to receive(:find_or_create_by_name).with(tax, nil).and_return item
        subject.send :internal_id_for, "tax"

        expect(subject.non_inventory_item_service).to receive(:find_or_create_by_name).with(discount, nil).and_return item
        subject.send :internal_id_for, "discount"
      end
    end

    context "account for both taxes and discounts in invoice[adjustments]" do
      subject do
        described_class.new(config, invoice: Factories.invoice_taxes_and_discounts_payload)
      end

      it "builds both tax and discount line" do
        NetsuiteIntegration::Services::Customer.any_instance.stub address_exists?: true

        VCR.use_cassette('invoice/taxes_and_discounts') do
          expect(subject.create).to be

          rates = subject.sales_invoice.item_list.items.map(&:rate)
          expect(rates).to include(-5)
          expect(rates).to include(25)
        end
      end
    end

    context "existing invoice" do
      let(:existing_invoice) do
        double("SalesOrder", internal_id: Time.now, external_id: 1.minute.ago)
      end

      # other objects, e.g. Customer Deposit depend on sales_invoice.external_id being set
      it "sets both internal_id and external id on new sales invoice object" do
        described_class.any_instance.stub_chain :sales_invoice_service, find_by_external_id: existing_invoice

        expect(subject.sales_invoice.external_id).to eq existing_invoice.external_id
        expect(subject.sales_invoice.internal_id).to eq existing_invoice.internal_id
      end

      it "updates the invoice along with customer address" do
        VCR.use_cassette('invoice/update_invoice_customer_address') do
          subject = described_class.new(config, invoice: Factories.update_invoice_customer_address_payload)
          expect(subject.update).to be
        end
      end
    end

    context 'netsuite instance requires Department' do
      subject do
        config['netsuite_department_id'] = 5
        described_class.new(config, { invoice: Factories.add_invoice_department_payload })
      end

      it 'still can create sales invoice successfully' do
        VCR.use_cassette('invoice/set_department') do
          expect(subject.create).to be
        end
      end
    end

    context "setting up customer" do
      subject do
        described_class.any_instance.stub_chain :sales_invoice_service, :find_by_external_id
        described_class.new(config, { invoice: Factories.add_invoice_department_payload })
      end

      let(:customer_instance) { double("Customer", errors: [double(message: "hey hey")]) }

      before do
        subject.stub_chain :customer_service, :find_by_external_id
        subject.stub_chain :customer_service, :create
        subject.stub_chain :customer_service, customer_instance: customer_instance
      end

      it "shows detailed error message" do
        expect {
          subject.set_up_customer
        }.to raise_error "hey hey"
      end
    end

    context "non inventory items" do
      subject do
        described_class.any_instance.stub_chain :sales_invoice_service, :find_by_external_id
        described_class.new(config, { invoice: Factories.add_invoice_department_payload })
      end

      before do
        subject.stub_chain :non_inventory_item_service, :find_or_create_by_name
        subject.stub_chain :non_inventory_item_service, :error_messages
      end

      it "raises if item not found or created" do
        expect {
          subject.internal_id_for "AAAAAaaaaaaaaaawwwwwwww"
        }.to raise_error NonInventoryItemException
      end
=end
    end
  end
end

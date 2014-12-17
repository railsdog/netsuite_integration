module NetsuiteIntegration
  module Services
    class Customer < Base
      attr_reader :customer_instance

      def find_by_external_id(email)
        NetSuite::Records::Customer.get({:external_id => email})
          # Silence the error
          # We don't care that the record was not found
      rescue NetSuite::RecordNotFound
      end

      # entity_id -> Customer name
      def create(payload)
        @customer_instance = customer = NetSuite::Records::Customer.new
        customer.email       = payload[:email]
        customer.external_id = payload[:email]

        if payload[:shipping_address]
          customer.first_name  = payload[:shipping_address][:firstname] || 'N/A'
          customer.last_name   = payload[:shipping_address][:lastname] || 'N/A'
          customer.phone       = payload[:shipping_address][:phone]
          fill_address(customer, payload[:shipping_address])
        else
          customer.first_name  = 'N/A'
          customer.last_name   = 'N/A'
        end

        handle_extra_fields customer, payload[:netsuite_customer_fields]

        # Defaults
        customer.is_person   = true
        # I don't think we need to make the customer inactive
        # customer.is_inactive = true

        if customer.add
          customer
        else
          false
        end
      end

      def handle_extra_fields(record, extra_fields)
        if extra_fields && extra_fields.is_a?(Hash)
          extra = {}
          extra_fields.each do |k, v|

            method = "#{k}=".to_sym
            ref_method = if k =~ /_id$/ || k =~ /_ref$/
                           "#{k[0..-4]}=".to_sym
                         end

            if record.respond_to? method
              extra[k.to_sym] = record.send method, v
            elsif ref_method && record.respond_to?(ref_method)
              extra[k[0..-4].to_sym] = record.send ref_method, NetSuite::Records::RecordRef.new(internal_id: v)
            end
          end

          extra
        end || {}
      end

      def update_attributes(customer, attrs)
        attrs.delete :id
        attrs.delete :created_at
        attrs.delete :updated_at

        # Converting string keys to symbol keys
        # Netsuite gem does not like string keys
        attrs = Hash[attrs.map{|(k,v)| [k.to_sym,v]}]

        if customer.update attrs
          customer
        else
          false
        end
      end

      def address_exists?(customer, payload)
        puts("#TS address_exists?")
        current = address_hash(payload)

        puts("#TS Results of existing_addresses : [#{existing_addresses(customer)}]")

        existing_addresses(customer).any? do |address|
          puts("#TS check address? #{address == current}")
          address.delete :default_shipping
          address == current
        end
      end

      def set_or_create_default_address(customer, payload)

        puts("#TS set_or_create_default_address #{payload.inspect}")

        attrs = [ address_hash(payload).update({ default_shipping: true }) ]

        existing = existing_addresses(customer).map do |a|
          puts("#TS existing_addresses #{a.inspect}")
          a[:default_shipping] = false
          a
        end

        puts("#TS customer.update  #{attrs.push(existing).flatten.inspect}")

        customer.update addressbook_list: { addressbook: attrs.push(existing).flatten }
      end

      def add_address(customer, payload)
        return if address_exists?(customer, payload)

        puts("#TS address_exists? false - add address")

        customer.update addressbook_list: {
                            addressbook: existing_addresses(customer).push(address_hash(payload))
                        }
      end

      def address_hash(payload)
        {
            addr1: payload[:address1],
            addr2: payload[:address2],
            zip: payload[:zipcode],
            city: payload[:city],
            state: StateService.by_state_name(payload[:state]),
            country: CountryService.by_iso_country(payload[:country]),
            phone: payload[:phone].to_s.gsub(/([^0-9]*)/, "")
        }
      end

      private

      def existing_addresses(customer)
          customer.addressbook_list.addressbooks.map do |abook|
            {
                default_shipping: abook.default_shipping,
                addr1: abook.addressbook_address.addr1.to_s,
                addr2: abook.addressbook_address.addr2.to_s,
                zip: abook.addressbook_address.zip.to_s,
                city: abook.addressbook_address.city.to_s,
                state: abook.addressbook_address.state.to_s,
                country: abook.addressbook_address.country.to_s,
                phone: abook.addressbook_address.addr_phone.to_s.gsub(/([^0-9]*)/, "")
            }
          end
      end

      def fill_address(customer, payload)
        if payload[:address1].present?
          customer.addressbook_list = {
              addressbook: address_hash(payload).update({ default_shipping: true })
          }
        end
      end


    end
  end
end

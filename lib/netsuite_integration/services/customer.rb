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

      def default_ship_addressbook(customer)
        customer.addressbook_list.addressbooks.find { |a| a.default_shipping == true }
      end

      def address_exists?(customer, payload)
        current = address_hash(payload)

        existing_addresses(customer).any? { |address| address == current }
      end

      def set_or_create_default_address(customer, payload)

        #TS 2014_2 - address now in sub type Address within each addressbook
        # set existign address to be non default
        existing = customer.addressbook_list.addressbooks.map do |abook|
          {
              default_shipping: false,
              addressbook_address: to_hash(abook.addressbook_address, :netsuite)
          }
        end

        puts("#TS customer.update  #{existing.flatten.inspect}")

        customer.update addressbook_list: { addressbook: existing.flatten }

        attrs = [{
            default_shipping: true,
            addressbook_address: address_hash(payload)
        }]

        puts("#TS customer.add  #{attrs.inspect}")

        customer.update addressbook_list: { addressbook: attrs }


      end

      def add_address(customer, payload)
        return if address_exists?(customer, payload)

        puts("#TS address_exists? false - add address")

        customer.update addressbook_list: {
                            addressbook: existing_addresses(customer).push(address_hash(payload))
                        }
      end

      # Convert Wombat payload to Netsuite - relevant fields only; comparable
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

      # Convert Wombat payload into full hash as per Netsuite::Record::Address
      def to_netsuite_hash(payload)
        {
            :addr1            => payload[:address1].to_s,
            :addr2            => payload[:address2].to_s,
            :addr3            => "",
            :attention        => "",
            :addressee        => "",
            :addr_phone       => payload[:phone].to_s.gsub(/([^0-9]*)/, ""),
            :addr_text        => payload[:addr_text].to_s,
            :city             => payload[:city].to_s,
            :state            => StateService.by_state_name(payload[:state]),
            :zip              => payload[:zipcode].to_s,
            :country          => CountryService.by_iso_country(payload[:country]),
            :override         => ""
        }
      end

      # Convert a NetSuite address into hash
      def to_hash(address, keys = :wombat)
        puts "to_hash => NS ADDRESS #{address.to_hash.inspect}"

        if(keys == :wombat)
          {
              :address1 => address.addr1,
              :address2 =>address.addr2.to_s,
              :zipcode => address.zip,
              :city => address.city,
              :state => address.state,
              :country => CountryService.by_iso_country(address.country.to_s),
              :phone => address.addr_phone.to_s.gsub(/([^0-9]*)/, "")
          }
        else
          {
              addr1:    address.addr1.to_s,
              addr2:    address.addr2.to_s,
              zip:      address.zip.to_s,
              city:     address.city.to_s,
              state:    address.state.to_s,
              country:  CountryService.by_iso_country(address.country.to_s),
              phone:    address.addr_phone.to_s.gsub(/([^0-9]*)/, "")
          }
        end
      end

      private

      def existing_addresses(customer)
          customer.addressbook_list.addressbooks.map do |abook|
            # TS 2014_" - address fields noved off AddressBook to Address
            to_hash(abook.addressbook_address, :netsuite)
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

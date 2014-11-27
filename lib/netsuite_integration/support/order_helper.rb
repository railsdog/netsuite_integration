# DRY up some of the common features of handling Orders

module NetsuiteIntegration

  module OrderHelper


    def set_up_customer
      if customer = customer_service.find_by_external_id(order_payload[:email])
        if !customer_service.address_exists? customer, order_payload[:shipping_address]
          customer_service.set_or_create_default_address customer, order_payload[:shipping_address]
        end
      else
        customer = customer_service.create(order_payload.dup)
      end

      unless customer
        message = if customer_service.customer_instance && customer_service.customer_instance.errors.is_a?(Array)
                    customer_service.customer_instance.errors.map(&:message).join(", ")
                  end

        raise CreationFailCustomerException, message
      end

      NetSuite::Records::RecordRef.new(internal_id: customer.internal_id)
    end


    def item_reference(item)
      item[:name] || item[:id] || item[:product_id]
    end

    def default_preferences
      {
          pageSize: 80,
          bodyFieldsOnly: false
      }
    end


    def build_bill_address
      if payload = order_payload[:billing_address]
        NetSuite::Records::BillAddress.new({
                                               bill_addressee: "#{payload[:firstname]} #{payload[:lastname]}",
                                               bill_addr1: payload[:address1],
                                               bill_addr2: payload[:address2],
                                               bill_zip: payload[:zipcode],
                                               bill_city: payload[:city],
                                               bill_state: Services::StateService.by_state_name(payload[:state]),
                                               bill_country: Services::CountryService.by_iso_country(payload[:country]),
                                               bill_phone: payload[:phone].gsub(/([^0-9]*)/, "")
                                           })
      end
    end

    def build_ship_address
      if payload = order_payload[:shipping_address]
        NetSuite::Records::ShipAddress.new({
                                               ship_addressee: "#{payload[:firstname]} #{payload[:lastname]}",
                                               ship_addr1: payload[:address1],
                                               ship_addr2: payload[:address2],
                                               ship_zip: payload[:zipcode],
                                               ship_city: payload[:city],
                                               ship_state: Services::StateService.by_state_name(payload[:state]),
                                               ship_country: Services::CountryService.by_iso_country(payload[:country]),
                                               ship_phone: payload[:phone].gsub(/([^0-9]*)/, "")
                                           })
      end
    end

    def handle_extra_fields
      if order_payload[:netsuite_order_fields] && order_payload[:netsuite_order_fields].is_a?(Hash)
        extra = {}
        order_payload[:netsuite_order_fields].each do |k, v|

          method = "#{k}=".to_sym
          ref_method = if k =~ /_id$/ || k =~ /_ref$/
                         "#{k[0..-4]}=".to_sym
                       end

          ref_method = ref_method == :class= ? :klass= : ref_method

          if sales_order.respond_to? method
            extra[k.to_sym] = sales_order.send method, v
          elsif ref_method && sales_order.respond_to?(ref_method)
            extra[k[0..-4].to_sym] = sales_order.send ref_method, NetSuite::Records::RecordRef.new(internal_id: v)
          end
        end

        extra
      end || {}
    end


    def internal_id_for(type)

      name = @config.fetch("netsuite_item_for_#{type.pluralize}", "Store #{type.capitalize}")

      if item = non_inventory_item_service.find_or_create_by_name(name, order_payload[:netsuite_non_inventory_fields])
        item.internal_id
      else
        raise NonInventoryItemException, "Couldn't create item #{name}: #{non_inventory_item_service.error_messages}"
      end
    end


    def verify_errors(object)
      unless (errors = (object.errors || []).select {|e| e.type == "ERROR"}).blank?
        text = errors.inject("") {|buf, cur| buf += cur.message}

        raise StandardError.new(text) if text.length > 0
      else
        object
      end
    end

  end
end

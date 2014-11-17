module NetsuiteIntegration

  class Invoice < Base

    attr_reader :order_payload, :invoice, :existing_invoice


    def initialize(config, payload = {})
      super config, payload

      @order_payload = payload[:order]

      # TODO  do we actually need to check for an existing invoice ?
      # @existing_invoice = invoice_service.find_by_external_id(order_payload[:number] || order_payload[:id])
      # puts "EXISTING :#{existing_invoice} "

      order_id = @order_payload['number']

      @invoice = NetSuite::Records::Invoice.new({  tax_rate: 0,
                                                   is_taxable: false,
                                                   external_id: order_id
                                                })
    end

    def import

      location = NetSuite::Records::Location.get( :internal_id => 4  )

      invoice.location = location

      puts "#TS IN INVOICE #{location}"

      invoice.entity = set_up_customer
      puts "\n\n#TS Done Customer : #{invoice.entity.inspect}\n"

      invoice.item_list = build_item_list
      puts "\n\ **** #TS Done item_list : #{invoice.item_list.inspect} ***\n\n"

      invoice.transaction_bill_address = build_bill_address

      invoice.shipping_cost = order_payload[:totals][:shipping]
      invoice.transaction_ship_address = build_ship_address

      #TODO - custom Placed On DAate in NS invoice.tran_date = order_payload[:placed_on]

      # TODO not sure any reqment for this
      #handle_extra_fields invoice, :netsuite_invoice_fields

      puts "#TS **** ADD AN INVOICE **** #{invoice}"

      invoice.add

      verify_errors(invoice)
    end


    private

    # TODO - copied from invoice so DRY this .. seperate module ?cos cannot make Order base of Invoice

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

      puts "Assign Customer : @ #{customer.internal_id}"

      NetSuite::Records::RecordRef.new(internal_id: customer.internal_id)
    end

    def build_item_list

      @item_list = []

      order_payload[:line_items].map do |item|

        item_id= item[:name] || item[:sku] || item[:product_id]

        non_inventory_item_search = NetsuiteIntegration::Services::NonInventoryItem.new(config)

        netsuite_item = non_inventory_item_search.find_by_name("6-Month Crate Subscription")

        unless netsuite_item
          raise NetSuite::RecordNotFound, "Non Inventory Item \"#{item_id}\" not found in NetSuite"
        end

        puts "Creating for InvoiceItem : NonInventoryItem : #{netsuite_item.inspect}"

        invoice_item = NetSuite::Records::InvoiceItem.new({
                                                              item: { internal_id: netsuite_item.internal_id },
                                                              quantity: item[:quantity],
                                                              amount: item[:quantity] * item[:price],
                                                              # Force tax rate to 0. NetSuite might create taxes rates automatically which
                                                              # will cause the sales order total to differ from the order in the Spree store
                                                              tax_rate1: 0
                                                          })

        @item_list << invoice_item

      end   # Spree item list

      puts "\nCreated InvoiceItemList  #{@item_list.size} : #{@item_list}\n"

      puts "Now Sorting Tax/Discount"

      # NetSuite treats taxes and discounts as seperate line items.

      ["tax", "discount", "shipping"].map do |type|

        value = order_payload[:adjustments].sum do |hash|
          if hash[:name].to_s.downcase == type.downcase
            hash[:value]
          else
            0
          end
        end


        @item_list << NetSuite::Records::InvoiceItem.new({ item: { internal_id: internal_id_for(type) },
                                                             rate: value
                                                          }) if(value != 0)
      end

      puts "\n\nCreating NetSuite::Records::InvoiceItemList from #{@item_list.size} : #{@item_list}"

      NetSuite::Records::InvoiceItemList.new(item: @item_list)
    end

    def basic_criteria
      [
          {
              field: 'type',
              operator: 'anyOf',
              type: 'SearchEnumMultiSelectField',
              value: item_type_to_fetch
          },
          {
              field: 'isInactive',
              value: false
          }
      ]
    end

    def default_preferences
      {
          pageSize: 80,
          bodyFieldsOnly: false
      }
    end

    def internal_id_for(type)
      name = @config.fetch("netsuite_item_for_#{type.pluralize}", "Store #{type.capitalize}")
      if item = non_inventory_item_service.find_or_create_by_name(name, order_payload[:netsuite_non_inventory_fields])
        item.internal_id
      else
        raise NonInventoryItemException, "Couldn't create item #{name}: #{non_inventory_item_service.error_messages}"
      end
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

    # See ItemTypes examples here https://system.netsuite.com/help/helpcenter/en_US/SchemaBrowser/lists/v2013_2_0/accountingTypes.html#listAcctTyp:ItemType
    def item_type_to_fetch
      if (item_types = config["netsuite_item_types"]).present?
        item_types.split(";").map(&:strip).map do |item_type|
          # need this hack because of inconsistent type naming
          # https://github.com/spree/netsuite_endpoint/issues/7#issuecomment-41196467
          case item_type
            when 'AssemblyItem'
              '_assembly'
            when 'KitItem'
              '_kit'
            else
              "_#{item_type[0].downcase}#{item_type[1..-1]}"
          end
        end
      else
        ['_inventoryItem']
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

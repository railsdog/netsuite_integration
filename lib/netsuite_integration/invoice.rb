module NetsuiteIntegration

  class Invoice < Base

    include NetsuiteIntegration::OrderHelper

    attr_reader :order_payload, :invoice, :existing_invoice


    def initialize(config, payload = {})
      super config, payload

      @order_payload = payload[:order]

      logger.debug("Start Invoice for #{order_reference}")

      @invoice = NetSuite::Records::Invoice.new({  tax_rate: 0,
                                                   is_taxable: false,
                                                   external_id: order_reference
                                                })
    end

    def create

      logger.debug("In create - search existing Invoice :external_id => #{order_reference}")

      existing_invoice =  begin
            #NetSuite::Records::Invoice.get({:external_id => order_reference})
                            nil
      rescue NetSuite::RecordNotFound
        nil
      rescue => e
        logger.error("Failed in create to search NetSuite for Invoice")
        logger.error(e.inspect)
        raise
      end

      logger.debug("In create - check for existing Invoice #{order_reference}")

      if(existing_invoice)
        raise NetSuite::InitializationError, "NetSuite Invoice already raised for Order \"#{order_reference}\""
      end

      logger.debug("Search for Location :internal_id => #{config['netsuite_location_internalid']}")

      if(config['netsuite_location_internalid'].present?)
        location = NetSuite::Records::Location.get( :internal_id => config['netsuite_location_internalid'] )

        invoice.location = location
      end

      logger.debug("In create - memo #{order_reference}")

      if(config['netsuite_save_ref_in_memo'].present?)
        invoice.memo = order_reference
      end

      logger.debug("Calling set_up_customer")

      invoice.entity = set_up_customer

      logger.debug("Calling build_item_list")

      invoice.item_list = build_item_list

      invoice.shipping_cost = order_payload[:totals][:shipping]

      logger.debug("Calling build_bill_address")
      invoice.transaction_bill_address = build_bill_address

      logger.debug("Calling build_ship_address")
      invoice.transaction_ship_address = build_ship_address

      handle_extra_fields

      logger.debug("Adding Invoice to NetSuiter")
      invoice.add

      verify_errors(invoice)
    end


    private


    def build_item_list

      @item_list = []

      order_payload[:line_items].map do |item|

        item_id = item_reference(item)

        non_inventory_item_search = NetsuiteIntegration::Services::NonInventoryItem.new(config)

        netsuite_item = non_inventory_item_search.find_by_name(item_id)

        unless netsuite_item
          raise NetSuite::RecordNotFound, "Non Inventory Item [#{item_id}] not found in NetSuite"
        end

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

      # NetSuite treats taxes and discounts as seperate line items.

      ["tax", "discount"].map do |type|

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

      #puts "\n\nCreating NetSuite::Records::InvoiceItemList from #{@item_list.size} : #{@item_list}"

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
        ['_nonInventoryItem']
      end
    end

  end
end

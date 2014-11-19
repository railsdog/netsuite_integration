module NetsuiteIntegration

  class Invoice < Base

    include NetsuiteIntegration::OrderHelper

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

    def create

      if(config['netsuite_location_internalid'].present?)
        location = NetSuite::Records::Location.get( :internal_id => config['netsuite_location_internalid'] )

        invoice.location = location
      end

      invoice.entity = set_up_customer

      invoice.item_list = build_item_list

      invoice.shipping_cost = order_payload[:totals][:shipping]

      invoice.transaction_bill_address = build_bill_address
      invoice.transaction_ship_address = build_ship_address

      handle_extra_fields

      invoice.add

      verify_errors(invoice)
    end


    private

    def build_item_list

      @item_list = []

      order_payload[:line_items].map do |item|

        item_id= item[:name] || item[:id] || item[:product_id]

        non_inventory_item_search = NetsuiteIntegration::Services::NonInventoryItem.new(config)

        netsuite_item = non_inventory_item_search.find_by_name("6-Month Crate Subscription")

        unless netsuite_item
          raise NetSuite::RecordNotFound, "Non Inventory Item \"#{item_id}\" not found in NetSuite"
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

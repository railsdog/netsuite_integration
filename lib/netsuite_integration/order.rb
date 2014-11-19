module NetsuiteIntegration
  class Order < Base
    attr_reader :config, :collection, :order_payload, :sales_order,
      :existing_sales_order

    include NetsuiteIntegration::OrderHelper

    def initialize(config, payload = {})
      super(config, payload)

      @config = config
      @order_payload = payload[:order]

      @existing_sales_order = sales_order_service.find_by_external_id(order_payload[:number] || order_payload[:id])

      if existing_sales_order
        @sales_order = NetSuite::Records::SalesOrder.new({
          internal_id: existing_sales_order.internal_id,
          external_id: existing_sales_order.external_id
        })
      else
        @sales_order = NetSuite::Records::SalesOrder.new({
          order_status: '_pendingFulfillment',
          external_id: order_payload[:number] || order_payload[:id]
        })

        # depending on your NS instance a custom form will need to be set to close the sales order
        if (custom_form_id = config['netsuite_sales_order_custom_form_id']).present?
          @sales_order.custom_form = NetSuite::Records::RecordRef.new(internal_id: custom_form_id)
        end
      end
    end

    def imported?
      @existing_sales_order
    end

    def create
      sales_order.entity = set_up_customer
      sales_order.item_list = build_item_list

      sales_order.transaction_bill_address = build_bill_address

      sales_order.shipping_cost = order_payload[:totals][:shipping]
      sales_order.transaction_ship_address = build_ship_address

      sales_order.tran_date = order_payload[:placed_on]

      if (department_id = config['netsuite_department_id']).present?
        sales_order.department = NetSuite::Records::RecordRef.new(internal_id: department_id)
      end

      handle_extra_fields

      if sales_order.add
        fresh_sales_order = sales_order_service.find_by_external_id(order_payload[:number] || order_payload[:id])
        sales_order.tran_id = fresh_sales_order.tran_id
        # need entity on sales_order for CustomerDeposit.customer
        sales_order.entity = fresh_sales_order.entity
        sales_order
      end
    end

    def update
      fields = {
        entity: set_up_customer,
        item_list: build_item_list,
        transaction_bill_address: build_bill_address,
        shipping_cost: order_payload[:totals][:shipping],
        transaction_ship_address: build_ship_address
      }

      sales_order.update fields.merge(handle_extra_fields)
    end

    def paid?
      if order_payload[:payments]
        payment_total = order_payload[:payments].sum { |p| p[:amount] }
        order_payload[:totals][:order] <= payment_total
      else
        false
      end
    end

    def errors
      if sales_order && sales_order.errors.is_a?(Array)
        self.sales_order.errors.map(&:message).join(", ")
      end
    end


    private

    def build_item_list
      sales_order_items = order_payload[:line_items].map do |item|

        reference = item[:sku] || item[:product_id]
        unless inventory_item = inventory_item_service.find_by_item_id(reference)
          raise NetSuite::RecordNotFound, "Inventory Item \"#{reference}\" not found in NetSuite"
        end

        NetSuite::Records::SalesOrderItem.new({
          item: { internal_id: inventory_item.internal_id },
          quantity: item[:quantity],
          amount: item[:quantity] * item[:price],
          # Force tax rate to 0. NetSuite might create taxes rates automatically which
          # will cause the sales order total to differ from the order in the Spree store
          tax_rate1: 0
        })
      end

      # Due to NetSuite complexity, taxes and discounts will be treated as line items.
      ["tax", "discount"].map do |type|
        value = order_payload[:adjustments].sum do |hash|
          if hash[:name].to_s.downcase == type.downcase
            hash[:value]
          else
            0
          end
        end

        if value != 0
          sales_order_items.push(NetSuite::Records::SalesOrderItem.new({
            item: { internal_id: internal_id_for(type) },
            rate: value
          }))
        end
      end

      NetSuite::Records::SalesOrderItemList.new(item: sales_order_items)
    end


  end
end

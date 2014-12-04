# Temporary home for this logic which needs to be moved to external config somehow
# or maybe into Wombat as a Transform

# Based on app/models/spree/subscription/order_handler.rb

class LootCrateSpecifics

  # We need to know "which month" these crates correspond to.
  # We need this information because the date is used to generate the order number, which
  # is of particular importance in ShipStation.
  #
  # We can either get this (eventually) from metadata contained in the product (via NetSuite),
  # or we can just infer it from the date we pass in.  I'm going with the latter for now.
  #
  # From: https://help.lootcrate.com/hc/en-us/articles/200574695-When-are-Loot-Crates-sent-out-
  #
  # Loot Crates are sent out once each month, scheduled to begin shipping on the 20th unless otherwise specified.
  # Signups are taken until 9pm PT on the 19th.
  # If you signup after 9PM PT (*) on the 19th, your first crate will come in the following month.
  #
  # For example, if you signed up on the 23rd of January, the first crate you’d receive would be our February crate.
  #
  # See Jeff's diagram: https://drive.google.com/a/lootcrate.com/file/d/0Bx0wOmsVHV96WEpaeFh4TVNnUU0/edit?usp=sharing

  # For example, If 'now' is Sept. 19 (EST), We assign the September crate (they barely made it)
  #              If 'now' is Sept. 20 (EST), We assign the October crate  (they need to wait for the next crate)

  # * Note that Jeff is convinced (and has coded it below) that the text above should read 'on or after'.
  # If someone signs up on the 19th at 9:00:00 PST, their rebill date will be on the 20th, not the 19th.
  # The rebill date drives whether or not you are due a crate for the month.
  #
  # From a conversation with Hannah: "Any charges between September 20 and October 19th pay for October's crate".
  #
  # So, we need to ensure that if the signup occurs exactly on the 20th at 00:00:00 (EST), your rebill will
  # be on the 20th, so we do not want to give you credit for signing up on the 19th.
  # See my comments in the subscription_converter (bottom of file) as well


  # N.B -STATTER - Format saved in NS slightly different to the Spree code
  # requires  "December 2014" rather than main site's  "DEC2014"

  def self.month_year_for_date(d)

    cutoff_for_this_month = DateTime.strptime("#{d.month}/19/#{d.year} 21:00:00 PDT", "%m/%d/%Y %H:%M:%S %Z")

    x = (d < cutoff_for_this_month) ? d : d + 1.month

    "#{I18n.t('date.month_names')[x.month]} #{x.year}"
  end

  def self.item_search_prefix
    "#{month_year_for_date(DateTime.now)} Crate "
  end


end
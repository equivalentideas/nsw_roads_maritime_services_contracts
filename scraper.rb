# Scraper to run on morph.io

# remove whitespace
def cleanup_string(string)
  string.delete("\r\n\t").gsub(/\s$/, "").gsub(/^\s/, "")
end

def format_key(key_text)
  key_text = key_text.downcase
  # strip out explanation stuff
  key_text = key_text.gsub("(based on unspsc)", "").gsub("(incl. abn & acn)", "")
  # swap "/" for " or "
  key_text = key_text.gsub("/", " or ")
  # strip stray whitespace, punctuation and make spaces underscores
  key = key_text.gsub(/^\s/, "").gsub(/\s$/, "").gsub("'", "").gsub(",", "").gsub(" ", "_").gsub("-", "_")
  key.to_sym
end

def format_date(raw_date)
  Date.parse(raw_date, '%d-%b-%Y ').to_s
end

def parse_contract_listing(page, last_updated)
  table = page.at('#main-content table')
  rows = table.css('> tr')
  contract_award_notice = {}

  contract_award_notice[:last_updated] = last_updated
  contract_award_notice[:url] = page.uri.to_s
  contract_award_notice[:date_scraped] = Date.today.to_s

  # debug output
  p contract_award_notice[:url]

  # Because I cannot predict the number of rows, or what key and value they contain,
  # I'm scraping the keys and values. This feels very fragile. If you have a better
  # solution, let me know please :)
  rows.each do |row|
    # Get the standard key value rows
    if !row.css('> th').empty? && !row.css('> td').empty?
      key = format_key(row.at(:th).text)

      # Their keys for contractor address and agency address are dupes,
      # prepend agency_ second time round
      key = ("agency_" + key.to_s).to_sym if contract_award_notice.has_key?(key)

      if key == :publish_date
        value = format_date(row.at(:td).text)
      elsif key == :contract_duration
        contract_duration = cleanup_string(row.at(:td).text).gsub(" to", "").split
        contract_award_notice[:contract_start_date] = format_date(contract_duration[0])
        contract_award_notice[:contract_end_date] = format_date(contract_duration[1])
      else
        value = cleanup_string(row.at(:td).text)
      end
      # Get the rows with <p><strong> for keys
    elsif row.css('> th').empty? && row.css('> td > p').count > 1
      key = format_key(row.search(:p)[0].text)

      if key == :contract_value || key == :amended_contract_value
        key = (key.to_s + "_est").to_sym
        value = cleanup_string(row.search(:p)[1..-1].text).gsub(" (Estimated Value of the Project)", "").delete("$,").to_f
      else
        value = cleanup_string(row.search(:p)[1..-1].text)
      end
      # Get the row with the table
    elsif !row.search(:table).empty? && row.css('table tr').count > 1
      key = :tender_evaluation_criteria

      # Get the evaluation criteria from the table
      criteria = []
      row.search(:tr)[1..-1].each do |r|
        s = r.search(:td)[0].text
        if !r.search(:td)[1].text.empty?
          s = s + " (#{r.search(:td)[1].text} weighting)"
        end
        criteria.push(s)
      end

      value = criteria.join(", ")
    # Get the row with a table that's contains one row of text.
    # Lord knows why this exists :S see https://tenders.nsw.gov.au/rms/?event=public.cn.view&CNUUID=6211F76A-CE44-5ACA-D9FD7FD57AE06619
    # for example.
    elsif !row.search(:table).empty? && row.css('table tr').count == 1
      key = format_key(row.search(:p)[0].text)
      value = row.at(:table).inner_text
    end

    # only set the key and value here if a value is assigned
    if value
      # Use "" rather than the "-" they use for empty
      value = nil if value == "-"
      contract_award_notice[key] = value
    end
  end

  ScraperWiki.save_sqlite([:contract_award_notice_id], contract_award_notice, table_name = 'contracts')

  contractor = {
    name: contract_award_notice[:contractor_name],
    abn: (contract_award_notice[:abn].nil? ? "#{contract_award_notice[:contractor_name]} + (no ABN provided)" : contract_award_notice[:abn]),
    acn: contract_award_notice[:acn],
    street_address: contract_award_notice[:street_address],
    city: contract_award_notice[:town_or_city],
    state: contract_award_notice[:state_or_territory],
    postcode: contract_award_notice[:postcode],
    country: contract_award_notice[:country],
    contracts: contract_award_notice[:contract_award_notice_id]
  }

  # If we we've seen this contractor before
  if ScraperWiki.select("abn from contracts where abn='#{contractor[:abn]}'").count > 1
    current_contracts = ScraperWiki.select("contract_award_notice_id from contracts where abn='#{contractor[:abn]}'and contract_award_notice_id!='#{contract_award_notice[:contract_award_notice_id]}'").map{|c| c["contract_award_notice_id"]}
    contractor[:contracts] = contractor[:contracts] + ", " + current_contracts.join(', ')
  end

  ScraperWiki.save_sqlite([:abn], contractor, table_name = 'contractors')
end

require 'scraperwiki'
require 'mechanize'

agent = Mechanize.new

domain = "https://tenders.nsw.gov.au"

search_indexes = ["https://tenders.nsw.gov.au/rms/?event=public.advancedsearch.CNRedirect&invalidEventName=public.CN.search&type=cnEvent&publishFrom=&publishTo=&valueFrom=&valueTo=&supplierABN=&supplierName=&Postcode=&agencyStatus=-1&submit=Search"]

search_indexes.each do |index_url|
  # param for selecting pages of results in the index
  # each page has 15 rows. Page 1: startRow=0, Page 2: startRow=15 etc.
  start_row = 0

  while start_row >= 0
    index = agent.get(index_url + "&startRow=#{start_row}")
    page_contract_listings = index.at('#main-content').css('h2 + table')[1..-1]

    if !page_contract_listings.empty?
      page_contract_listings.each do |l|
        last_updated = DateTime.parse(cleanup_string(l.search(:tr).last.at('.last-updated').children.last.text), '%d-%b-%Y %l:%M%p').strftime('%Y-%m-%d %H:%M')
        page_link = l.search(:tr).last
        page = agent.get(domain + l.search(:tr).last.at(:a).attr(:href))
        parse_contract_listing(page, last_updated)
      end

      start_row = start_row + page_contract_listings.count
    else
      start_row = -1
    end
  end
end

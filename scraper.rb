# This is a template for a Ruby scraper on morph.io (https://morph.io)
# including some code snippets below that you should find helpful

def row_value(row)
  row.at(:td).text
end

# remove whitespace
def cleanup_string(string)
  string.delete("\r\n\t").gsub(/\s$/, "").gsub(/^\s/, "")
end

def format_key(key_text)
  key_text = key_text.downcase
  # strip out explaination stuff
  key_text = key_text.gsub("(based on unspsc)", "").gsub("(incl. abn & acn)", "")
  # swap "/" for " or "
  key_text = key_text.gsub("/", " or ")
  # strip stray whitespace, punctuation and make spaces underscores
  key = key_text.gsub(/^\s/, "").gsub(/\s$/, "").gsub("'", "").gsub(",", "").gsub(" ", "_")
  key
end

def format_date(raw_date)
  Date.parse(raw_date, '%d-%b-%Y ').to_s
end

require 'scraperwiki'
require 'mechanize'

agent = Mechanize.new
page = agent.get('https://tenders.nsw.gov.au/rms/?event=public.cn.view&CNUUID=0B37D3B9-C218-BEC9-F42508EA7D143595')
table = page.at('#main-content table')
rows = table.css('> tr')
contract_award_notice = {}

contract_award_notice["url"] = page.uri.to_s

# Because I cannot predict the number of rows, or what key and value they contain,
# I'm scraping the keys and values. This feels very fragile. If you have a better
# solution, let me know please :)
rows.each do |row|
  # Get the standard key value rows
  if !row.css('> th').empty? && !row.css('> td').empty?
    key = format_key(row.at(:th).text)

    if key == "publish_date"
      value = format_date(row.at(:td).text)
    elsif key == "contract_duration"
      contract_duration = cleanup_string(row.at(:td).text).gsub(" to", "").split
      contract_award_notice["contract_start_date"] = format_date(contract_duration[0])
      contract_award_notice["contract_end_date"] = format_date(contract_duration[1])
    else
      value = cleanup_string(row.at(:td).text)
    end
  # Get the rows with <p><strong> for keys
  elsif row.css('> th').empty? && row.css('> td > p').count > 1
    key = format_key(row.search(:p)[0].text)

    if key == "contract_value" || key == "amended_contract_value"
      key = key + "_est"
      value = cleanup_string(row.search(:p)[1..-1].text).gsub(" (Estimated Value of the Project)", "").delete("$,")
    else
      value = cleanup_string(row.search(:p)[1..-1].text)
    end
  # Get the row with the table
  elsif !row.search(:table).empty?
    key = "tender_evaluation_criteria"

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
  end

  # only set the key and value here if a value is assigned
  if value
    contract_award_notice[key] = value
  end
end

# # Write out to the sqlite database using scraperwiki library
# ScraperWiki.save_sqlite(["name"], {"name" => "susan", "occupation" => "software developer"})
#
# # An arbitrary query against the database
# ScraperWiki.select("* from data where 'name'='peter'")

# You don't have to do things with the Mechanize or ScraperWiki libraries.
# You can use whatever gems you want: https://morph.io/documentation/ruby
# All that matters is that your final data is written to an SQLite database
# called "data.sqlite" in the current working directory which has at least a table
# called "data".

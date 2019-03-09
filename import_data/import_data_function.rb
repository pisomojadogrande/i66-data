require 'json'
require 'net/http'
require 'rexml/document'
require 'aws-sdk-s3'

include REXML

S3 = Aws::S3::Client.new
DATA_S3_BUCKET = ENV['DATA_S3_BUCKET']

SMARTER_ROADS_TOKEN = ENV['SMARTER_ROADS_TOKEN']
SMARTER_ROADS_BASE_URI = "https://smarterroads.org/dataset/tree/29?token=#{SMARTER_ROADS_TOKEN}"


HOUR_FORMAT = '%Y/%m/%d/%H'

def fetch_data(query)
    uri = URI("#{SMARTER_ROADS_BASE_URI}#{query}")
    puts "fetching from #{uri}"
    r = Net::HTTP.get_response uri
    puts "#{uri} ==> #{r.inspect}"
    r.body
end

def fetch_data_for_hour(t)
    hour = t.strftime HOUR_FORMAT
    data = fetch_data "&id=TollingTripPricing-I66/#{hour}"
    JSON.parse(data).map {|x| x['id']}.sort
end

def find_latest_hour_entries
    t = Time.new + 3600
    entries_for_hour = []
    begin
        t -= 3600
        entries_for_hour = fetch_data_for_hour t
        puts "#{t.strftime(HOUR_FORMAT)}: #{entries_for_hour.inspect}"
    end while entries_for_hour.empty?
    entries_for_hour
end

def find_new_entries(entries)
    # TollingTripPricing-I66/2019/02/17/20/02
    # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    existing_keys = []
    if entries.first =~ /^(.*\/)\d+$/
        prefix = $1
        r = S3.list_objects_v2 :bucket => DATA_S3_BUCKET, :prefix => prefix
        puts r.inspect
        existing_keys = r.contents.map {|x| x.key }.sort.inspect
    end
    puts "existing keys: #{existing_keys.inspect}"

    new_keys = entries.select {|e| !existing_keys.include? e }
    puts "new keys to write: #{new_keys.inspect}"
    new_keys
end

def write_entry(entry)
    minute_entry = fetch_data "&id=#{entry}"
    puts "Minute entry: #{minute_entry}"
    minute_entry_o = JSON.parse minute_entry
    puts minute_entry_o.first.inspect
    
    download_uri = URI(minute_entry_o.first['a_attr']['href'])
    r = Net::HTTP.get_response download_uri
    puts "Data download result: #{r.inspect}"

    # The Glue XML crawler doesn't seem to be able to reckon with
    # this data, so we will convert it to CSV
    # The data is formatted as 
    # <data>
    #   <opt CalculatedDateTime="2019-03-08T21:24:00Z" StartZoneName="Capital Beltway End" ... />
    #   ... <opt />
    # </data>
    # Where the 'opt' rows contain the real data.
    # Infer the schema from the first such row, and then write a CSV values row for each
    xmldoc = Document.new r.body
    row_elements = xmldoc.root.elements
    if row_elements && !row_elements.empty?
        attr_keys = row_elements.first.attributes.keys.sort
        puts "Keys: #{attr_keys.inspect}"
        csv_string = attr_keys.join ','
        csv_string << "\n"

        row_elements.each do |row_element|
            csv_string << attr_keys.map { |k| row_element.attributes[k] }.join(',') << "\n"
        end

        puts "Writing to s3://#{DATA_S3_BUCKET}/#{entry}"
        S3.put_object(
            :bucket => DATA_S3_BUCKET,
            :key => entry,
            :content_type => 'text/plain; charset=utf-8',
            :body => csv_string.encode('utf-8')
        )
    end
    entry
end

def write_entries(entries)
    entries.map { |e| write_entry e }
end


def handler(event:, context:)
    puts "EVENT: #{JSON.generate(event)}"
    latest_hour_entries = find_latest_hour_entries
    new_entries = find_new_entries latest_hour_entries
    
    objects_written = write_entries new_entries

    {
        entries: new_entries,
        s3_bucket: DATA_S3_BUCKET,
        s3_keys_written: objects_written
    }
end

require 'json'
require 'net/http'
require 'aws-sdk-s3'

S3 = Aws::S3::Client.new
DATA_S3_BUCKET = ENV['DATA_S3_BUCKET']

SMARTER_ROADS_TOKEN = ENV['SMARTER_ROADS_TOKEN']
SMARTER_ROADS_BASE_URI = "https://smarterroads.org/dataset/tree/29?token=#{SMARTER_ROADS_TOKEN}&id=TollingTripPricing-I66"

HOUR_FORMAT = '%Y/%m/%d/%H'

def fetch_data_for_time(t)
    path = t.strftime HOUR_FORMAT
    uri = URI("#{SMARTER_ROADS_BASE_URI}/#{path}")
    puts "fetching from #{uri}"
    r = Net::HTTP.get_response uri
    puts "#{uri} ==> #{r.inspect}"
    JSON.parse(r.body).map {|x| x['id']}.sort
end

def find_latest_hour_entries
    t = Time.new + 3600
    entries_for_hour = []
    begin
        t -= 3600
        entries_for_hour = fetch_data_for_time t
        puts "#{t.strftime(HOUR_FORMAT)}: #{entries_for_hour.inspect}"
    end while entries_for_hour.empty?
    entries_for_hour
end



def handler(event:, context:)
    latest_hour_entries = find_latest_hour_entries

    {
        entries: latest_hour_entries
    }
end

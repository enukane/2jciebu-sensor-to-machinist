require "./omron-sensor.rb"
require "net/http"
require "uri"
require "json"
require "openssl"
require "pit"

MACHINIST_URL="https://gw.machinist.iij.jp/gateway"
machinist_account = Pit.get('machinist')

def convert_data2metrics(data)
  # { key:value, } to [ {"name": key, "data_point": { "value" : value } }, ]
  ary = []
  data.keys.each do |key|
    val = data[key]
    elm = { "name" => key, "data_point": {"value": val}}
    ary << elm
  end

  return ary
end

def generate_machinist_msg(data, account)
  metrics = convert_data2metrics(data)

  msg = {}
  msg["agent_id"] = account[:agent_id]
  msg["api_key"] = account[:key]
  msg["metrics"] = metrics

  return msg
end

def post_result(msg)
  url = URI(MACHINIST_URL)
  http = Net::HTTP.new(url.host, url.port)
  if url.scheme == "https"
    http.use_ssl = true
    http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  req = Net::HTTP::Post.new(url)
  req["content-type"] = "application/json"
  req.body = JSON.dump(msg)

  res = http.request(req)

  unless res and res.is_a?(Net::HTTPSuccess)
    puts "failed to post data #{res.code} #{res.message} #{res.body}"
  else
    puts "succeeded to post data"
  end
end

loop do
  sleep(30)
  data = try_get_data()
  next if data.nil?
  msg = generate_machinist_msg(data, machinist_account)
  post_result(msg)
end

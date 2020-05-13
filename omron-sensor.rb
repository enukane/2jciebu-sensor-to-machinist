require "serialport"
require "json"
require "timeout"

#command data to send => RB"P
#                            header => 4252
#data to be read: 26 byte
#[0]: 1
#[1]: 22
#[2]: 50
#[3]: 67
#[4]: e6
#[5]: a
#[6]: 68
#[7]: 12
#[8]: 45
#[9]: 0
#[10]: 48
#[11]: 4c
#[12]: f
#[13]: 0
#[14]: 4d
#[15]: 16
#[16]: 45
#[17]: 2
#[18]: 69
#[19]: 7
#[20]: 5d
#[21]: 1d
#[22]: 24
#[23]: 9
#[24]: 7
#[25]: 5
#["67", "e6", "a", "68", "12", "45", "0", "48", "4c", "f", "0", "4d", "16", "45", "2", "69", "7", "5d", "1d", "24", "9"]
#temp: 27.900000000000002 degC
#rh: 47.12 %RH
#lux: 69.0 lx
#pressure: 1002.568 hPa
#noise: 57.09 dB
#etvoc: 581 ppb
#eco2: 1897 ppm
#di: 75.17#


def dp msg
  puts msg if $debug
end

def dprint msg
  print msg if $debug
end

def send_cmd(serialport)
  buf = [ 0x52, 0x42, 0x05, 0x00, 0x01, 0x22, 0x50, 0xe2, 0xbb ]
  packed_buf = buf.pack("c*")
  dp "command data to send => #{packed_buf}\n"

  serialport.puts(packed_buf)
  nil
end

def fetch_len(serialport)
  data = serialport.read(4)
  frame = data.unpack("c*")
  dp "header frame => #{frame.map{|elm| elm.to_s(16)}}"

  header = (frame[1].to_i << 8) + frame[0].to_i
  dp "header => #{header.to_s(16)}"

  len = (frame[3].to_i << 8) + frame[2].to_i
  return len
end

def receive_command_result_with_timeout(serialport, len, timeout_sec=5)
  Timeout.timeout(timeout_sec) do
    buf = serialport.read(len).unpack("c*")
    return buf
  end
end

def receive_command_result_with_timeout2(serialport, len, timeout_sec=2)
  data = []
  Timeout.timeout(timeout_sec) do
    0.upto(len - 1) do |n|
      buf = serialport.read(1).unpack("C")[0]
      data << buf
      dp "[#{n}] #{buf.to_s(16)}"
    end
  end
  return data
end

def parse_result(data)
  # Table 82 Read response format
  formats = {
    "temp"  => { :from => 1, :to => 2, :base => 0.01, :unit => "degC" },
    "rh"    => { :from => 3, :to => 4, :base => 0.01, :unit => "%RH" },
    "lux"   => { :from => 5, :to => 6, :base => 1.00, :unit => "lx" },
    "pressure"  => { :from => 7, :to => 10, :base => 0.001, :unit => "hPa" },
    "noise" => { :from => 11, :to => 12, :base => 0.01, :unit => "dB" },
    "etvoc" => { :from => 13, :to => 14, :base => 1, :unit => "ppb" },
    "eco2"  => { :from => 15, :to => 16, :base => 1, :unit => "ppm" },
    "di"    => { :from => 17, :to => 18, :base => 0.01, :unit => "" },
    "heatstroke"  => { :from => 19, :to => 20, :base => 0.01, :unit => "debC" }
  }
  keys = formats.keys

  output = {}
  keys.each do |key|
    format = formats[key]
    value = data[format[:from]..format[:to]].reverse.inject{|m, e| (m << 8) + e} * format[:base]
    output[key] = value
    dp "#{key}: #{value} #{format[:unit]}"
  end

  return output
end

def get_data
  sp = SerialPort.new("/dev/ttyUSB0", 115200, 8, 1, 0)
  send_cmd(sp)
  len = fetch_len(sp)

  dp "len => #{len}"

  begin
    payload_crc = receive_command_result_with_timeout2(sp, len)
    sp.close
  rescue Timeout::Error => e
    sp.close
    raise "failed to get result (timeout)"
  end
  data = payload_crc[3..-1]
  dp data.map{|elm| elm.to_s(16)}

  return parse_result(data)
end

def try_get_data(max=20, interval=1)
  1.upto(max) do |n|
    sleep(interval)
    begin
      dp "trial #{n}:"
      data = get_data()
      return data
    rescue => e
      dp "trial #{n} failed, retry (#{e})"
    end
  end
  return nil
end


if __FILE__ == $0
  $debug = false || ENV["DEBUG"] == "1"
  data = try_get_data(20, 3)
  if data
    puts JSON.pretty_generate(data)
    exit(0)
  else
    puts "failed"
    exit(1)
  end
end

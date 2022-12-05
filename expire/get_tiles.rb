#!/usr/bin/ruby

require 'English'
require 'yaml'
require 'json'
require 'open-uri'
require 'net/http'
require 'http'


config = ENV.fetch('CONFIG', nil)
server_url = ENV.fetch('SERVER', nil)
cache_bypass_header = ENV.fetch('BYPASS', nil)


@config = YAML.safe_load(File.read(config), aliases: true)
ids = ARGV


def http_get(url)
  resp = HTTP.headers(@config['fetch_http_headers'] || {}).follow.get(url)
  raise resp if !resp.status.success?

  resp.body
end

def setting(url)
  JSON.parse(http_get(url))
end

def deg2num(lon_deg, lat_deg, zoom)
  lat_rad = lat_deg / 180 * Math::PI
  n = 2.0**zoom
  xtile = ((lon_deg + 180.0) / 360.0 * n).to_i
  ytile = ((1.0 - (Math.log(Math.tan(lat_rad) + (1 / Math.cos(lat_rad))) / Math::PI)) / 2.0 * n).to_i
  [xtile, ytile]
end

def download_url(server_uri, request_uri, cache_bypass_header)
  ret = Net::HTTP.start(server_uri.hostname, server_uri.port) { |http|
    req = Net::HTTP::Get.new(request_uri)
    req[cache_bypass_header] = 'true'
    http.request(req)
  }
  if ret.code != '200'
    puts request_uri
    puts ret.inspect
  end
end

def get_tiles(server_uri, request_uri, cache_bypass_header, bbox)
  path_template = request_uri.path
  0.upto(14).each{ |zoom|
    puts(zoom)
    minx, miny = deg2num(bbox[0][0], bbox[1][1], zoom)
    maxx, maxy = deg2num(bbox[1][0], bbox[0][1], zoom)
    [minx - 2, 0].max.upto([maxx + 2, (2**zoom) - 1].min).each{ |x|
      [miny - 2, 0].max.upto([maxy + 2, (2**zoom) - 1].min).each{ |y|
        request_uri.path = path_template.gsub('__x__', x.to_s).sub('__y__', y.to_s).gsub('__z__', zoom.to_s)
        download_url(server_uri, request_uri, cache_bypass_header)
      }
    }
  }
end


server_uri = URI(server_url)
@config['sources'].select{ |id, _source|
  ids.empty? || ids.include?(id)
}.select{ |id, source|
  keep = source.dig('cache', 'prefetch') != false
  if !keep
    puts("Skip #{id}")
  end
  keep
}.each{ |id, source|
  begin
    puts(id)

    data_api_url = source['sources']['partial']['fetcher']['data_api_url']
    config = setting("#{data_api_url}/settings.json")
    bbox = config['bbox_line']['coordinates']
    puts bbox.inspect

    key = source['key']
    url_template = "#{server_uri}/data/#{id}/__z__/__x__/__y__.pbf?key=#{key}"
    request_uri = URI(url_template)

    get_tiles(server_uri, request_uri, cache_bypass_header, bbox)
  rescue StandardError => e
    puts "Error during processing: #{$ERROR_INFO}"
    puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
  end
}

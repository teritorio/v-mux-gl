#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'open-uri'
require 'net/http'
require 'webcache'


@download_cache = WebCache.new(life: '6h', dir: '/data/cache')


def setting(url)
    setting = JSON.parse(@download_cache.get(url).content)
end

def deg2num(lon_deg, lat_deg, zoom)
    lat_rad = lat_deg / 180 * Math::PI
    n = 2.0 ** zoom
    xtile = ((lon_deg + 180.0) / 360.0 * n).to_i
    ytile = ((1.0 - Math.log(Math.tan(lat_rad) + (1 / Math.cos(lat_rad))) / Math::PI) / 2.0 * n).to_i
    [xtile, ytile]
end

def download_url(server_uri, request_uri, cache_bypass_header)
    ret = Net::HTTP.start(server_uri.hostname, server_uri.port) {|http|
        req = Net::HTTP::Get.new(request_uri)
        req['cache_bypass_header'] = 'true'
        http.request(req)
    }
    if ret.code != '200' then
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
        [minx - 2, 0].max.upto([maxx + 2, 2 ** zoom - 1].min).each{ |x|
            [miny - 2, 0].max.upto([maxy + 2, 2 ** zoom - 1].min).each{ |y|
                request_uri.path = path_template.gsub('__x__', x.to_s).sub('__y__', y.to_s).gsub('__z__', zoom.to_s)
                download_url(server_uri, request_uri, cache_bypass_header)
            }
        }
    }
end

config, server_url, cache_bypass_header = *ARGV
server_uri = URI(server_url)
config = YAML.safe_load(File.read(config), aliases: true)
config['sources'].each{ |id, source|
    puts(id)

    data_api_url = source['sources']['partial']['fetcher']['data_api_url']
    config = setting(data_api_url)
    bbox = config['bbox_line']['coordinates']
    puts bbox.inspect

    key = source['sources']['full']['key']
    host = source['hosts'][0]
    url_template = "http://#{host}/data/#{id}/__z__/__x__/__y__.pbf?key=#{key}"
    request_uri = URI(url_template)

    get_tiles(server_uri, request_uri, cache_bypass_header, bbox)
}

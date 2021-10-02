#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'open-uri'
require 'net/http'


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
        minx, miny = deg2num(bbox[0], bbox[3], zoom)
        maxx, maxy = deg2num(bbox[2], bbox[1], zoom)
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
config = YAML.load(File.read(config))
config['styles'].each{ |style_id, style|
    puts(style_id)
    id = style['id']
    bbox = style['bbox']
    key = style['sources']['full']['key']
    host = style['hosts'][0]
    url_template = "http://#{host}/data/#{id}/__z__/__x__/__y__.pbf?key=#{key}"
    request_uri = URI(url_template)

    get_tiles(server_uri, request_uri, cache_bypass_header, bbox)
}

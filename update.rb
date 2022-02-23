#!/usr/bin/ruby

require 'rubygems'
require 'bundler'
Bundler.setup

require 'yaml'
require 'json'
require 'set'
require 'deep_merge'
require 'webcache'
require 'nokogiri'


@download_cache = WebCache.new(life: '6h', dir: '/data/cache')


def setting(url, polygon)
    setting = JSON.parse(@download_cache.get(url).content)
    File.write(polygon, JSON.pretty_generate(setting['polygon']))
end


def menu(url, json)
    menu = JSON.parse(@download_cache.get(url).content)
    classes = menu.select{ |m|
        m['category']
    }.collect{|m|
        m['category']
    }.select{ |m|
        m['tourism_style_merge']
    }.collect{ |m|
        m['tourism_style_class']
    }.sort.uniq
    File.write(json, JSON.pretty_generate(classes))
end


def category_ids(ids)
    ids && ';' + ids.join(';') + ';'
end


def pois(pois_geojson, ontology)
    missing_classes = Set.new()
    pois_geojson = pois_geojson.select{ |feature|
        display = feature['properties']['display']
        display && display['tourism_style_class'] && display['tourism_style_class'] != ''
    }.collect{ |feature|
        p = feature['properties']
        id = p['metadata']['id']
        superclass, class_, subclass = p['display']['tourism_style_class']
        color = p['display'] && p['display']['color']
        if !color then
            begin
                onto = subclass ? ontology['superclass'][superclass]['class'][class_]['subclass'][subclass] : class_ ? ontology['superclass'][superclass]['class'][class_] : ontology['superclass'][superclass]
                raise if !onto
            rescue
                missing_classes << "#{superclass}/#{class_}/#{subclass}"
                next
            end
        end
        p = p.merge({
            id: id,
            category_ids: category_ids(p['metadata']['category_ids']),
            superclass: superclass,
            'class': class_,
            subclass: subclass,
            priority: onto && onto['priority'],
            zoom: onto && onto['zoom'],
            style: onto && onto['style'],
            color: color,
            popup_properties: p['editorial'] && p['editorial']['popup_properties'],
        })
        p['name:latin'] = p['name'] if p.key?('name')
        p.delete('metadata')
        p.delete('editorial')
        p.delete('display')

        {
            type: 'Feature',
            properties: Hash[p.collect{ |k, v| [k, v && v.kind_of?(Array) ? v.join(';') : v] }],
            geometry: feature['geometry'],
        }
    }

    missing_classes.each{ |mc|
        STDERR.puts "Missing #{mc}"
    }

    groups = pois_geojson.group_by{ |feature|
        feature[:geometry]['type'] == 'Point'
    }

    [groups[true] || [], groups[false] || []]
end


def merge_compact_multilinestring(tracks)
    # Count tracks at connection points
    ends = Hash.new { |h, k| h[k] = [] }
    tracks.each{ |track|
        ends[track[0]] << track
        ends[track[-1]] << track
    }

    # Exclude non mergable tracks
    merge_tracks = []
    ends.each{ |p, tracks|
        if tracks.size != 2 then
            merge_tracks += tracks
            ends.delete(p)
        end
    }
    merge_tracks = merge_tracks.uniq - ends.collect{ |p, tracks| tracks }.flatten(1)

    while(ends.size > 0) do
        p = ends.keys[0]
        tracks = ends[p]
        ends.delete(p)

        # Merge consecutive linestring
        tracks_0 = tracks[0]
        tracks_1 = tracks[1]
        if tracks[0][-1] != p then
            tracks[0] = tracks[0].reverse
        end
        if tracks[1][0] != p then
            tracks[1] = tracks[1].reverse
        end

        merge_track = tracks[0] + tracks[1][1..-1]

        # Update ends
        if ends.include?(merge_track[0]) || ends.include?(merge_track[-1]) then
            if ends.include?(merge_track[0]) then
                ends[merge_track[0]] = ends[merge_track[0]] - [tracks_0] + [merge_track]
            end
            if ends.include?(merge_track[-1]) then
                ends[merge_track[-1]] = ends[merge_track[-1]] - [tracks_1] + [merge_track]
            end
        else
            merge_tracks << merge_track
        end
    end

    merge_tracks
end


def gpx2geojson(gpx)
    doc = Nokogiri::XML(gpx)
    doc.remove_namespaces!
    {
        type: 'MultiLineString',
        coordinates: doc.xpath('/gpx/rte').collect{ |rte|
            rte.xpath('rtept').collect{ |pt|
                [pt.attribute('lon').to_s.to_f, pt.attribute('lat').to_s.to_f]
            }
        } + doc.xpath('/gpx/trk').collect{ |trk|
            trk.xpath('trkseg').collect{ |seg|
                seg.xpath('trkpt').collect{ |pt|
                    [pt.attribute('lon').to_s.to_f, pt.attribute('lat').to_s.to_f]
                }
            }
        }.flatten(1)
    }
end

def routes(routes_geojson)
    cache = WebCache.new(life: '30d', dir: '/data/routes-cache')

    routes_geojson.select{ |feature|
        !feature['properties']['route:gpx_trace'].nil?
    }.each{ |feature|
        feature['properties']['route:trace'] = cache.get(feature['properties']['route:gpx_trace']).content
    }.select{ |feature|
        !feature['properties']['route:trace'].nil?
    }.collect{ |feature|
        p = feature['properties']
        p.merge!({
            id: p['metadata']['id'],
            category_ids: category_ids(p['metadata']['category_ids']),
            color: p['display'] && p['display']['color'],
            popup_properties: p['editorial'] && p['editorial']['popup_properties'],
        })
        p['name:latin'] = p['name'] if p.key?('name')

        feature['geometry'] = gpx2geojson(feature['properties']['route:trace'])
        p.delete('route:trace')

        p.delete('metadata')
        p.delete('editorial')
        p.delete('display')

        feature['properties'] = Hash[p.collect{ |k, v| [k, v && v.kind_of?(Array) ? v.join(';') : v] }]
        feature
    }
end


def tippecanoe(pois_json, pois_layer, features_json, features_layer, mbtiles, attribution)
    system("""
        tippecanoe --force \
            --named-layer=#{pois_layer}:#{pois_json} \
            --named-layer=#{features_layer}:#{features_json} \
            --use-attribute-for-id=id \
            --convert-stringified-ids-to-numbers \
            --attribution='#{attribution}' \
            -o #{mbtiles}
    """)

    # TODO limiter par zoom dans le tuiles : ne marche pas
    # -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'
end


def build(source_id, source)
    fetcher = source['sources']['partial']['fetcher']
    data_api_url = fetcher['data_api_url']

    polygon = source['polygon']
    setting(data_api_url, polygon)

    classes = source['merge_layers']['poi_tourism']['classes']
    menu(data_api_url + '/menu', classes)

    ontology = JSON.parse(@download_cache.get(source['sources']['full']['ontology']['url']).content)
    ontology_overwrite = source['sources']['full']['ontology']['data'] || {}
    ontology.deep_merge!(ontology_overwrite)

    pois = JSON.parse(@download_cache.get(data_api_url + '/pois?short_description=true').content)
    pois_features = pois['features']

    mbtiles = source['sources']['partial']['mbtiles']

    pois_data, features_data = pois(pois_features, ontology)
    features_data += routes(pois_features)

    pois_json = mbtiles.gsub('.mbtiles', '-pois.geojson')
    File.write(pois_json, JSON.pretty_generate({
        type: 'FeatureCollection',
        features: pois_data
    }))

    features_json = mbtiles.gsub('.mbtiles', '-features.geojson')
    File.write(features_json, JSON.pretty_generate({
        type: 'FeatureCollection',
        features: features_data
    }))

    attribution = fetcher['attribution']
    tippecanoe(pois_json, 'poi_tourism', features_json, 'features_tourism', mbtiles, attribution)
end


config = YAML.load(File.read(ARGV[0])) # After update add "aliases: true"
config['sources'].each{ |source_id, source|
    begin
        puts(source_id)
        build(source_id, source)
    rescue => e
        puts "Error during processing: #{$!}"
        puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
    end
}

#!/usr/bin/ruby

require 'rubygems'
require 'bundler'
Bundler.setup

require 'yaml'
require 'json'
require 'set'
require 'http'
require 'webcache'
require 'nokogiri'


config = ENV.fetch('CONFIG', nil)
@config = YAML.load(File.read(config)) # After update add "aliases: true"

@config_path = @config['server']['config_path'] || ''

def http_get(url)
  resp = HTTP.headers(@config['fetch_http_headers'] || {}).follow.get(url)
  if resp.status.success?
    resp.body
  else
    raise resp
  end
end

@download_cache = WebCache.new(life: '6h', dir: '/data/cache')


def setting(url, polygon)
  setting = JSON.parse(http_get(url))
  File.write(polygon, JSON.pretty_generate(setting['polygon']))
end

def menu(url, json)
  menu = JSON.parse(http_get(url))
  classes = menu.collect{ |m|
    m['category']
  }.compact.select{ |m|
    m['style_merge'] && m['style_class']
  }.collect{ |m|
    m['style_class']
  }.sort.uniq
  File.write(json, JSON.pretty_generate(classes))
  menu
end

def category_ids(ids)
  ids && (';' + ids.join(';') + ';')
end

def class_ontology_condition(condition, _p)
  # _p is used in eval context
  !condition || eval(condition)
end

def class_ontology_select(o, oo, properties)
  oo && class_ontology_condition(oo['condition'], properties) ? o.merge(oo) : o
end

def class_ontology(superclass, class_, subclass, ontology, ontology_overwrite, properties)
  if subclass
    o = ontology.dig('superclass', superclass, 'class', class_, 'subclass', subclass)
    (o && class_ontology_select(
      o,
      ontology_overwrite.dig('superclass', superclass, 'class', class_, 'subclass', subclass),
      properties
    )) || nil
  elsif class_
    o = ontology.dig('superclass', superclass, 'class', class_)
    (o && class_ontology_select(
      o,
      ontology_overwrite.dig('superclass', superclass, 'class', class_),
      properties
    )) || nil
  else
    o = ontology.dig('superclass', superclass)
    (o && class_ontology_select(
      o,
      ontology_overwrite.dig('superclass', superclass),
      properties
    )) || nil
  end
end

def pois(menu, pois_geojson, ontology, ontology_overwrite)
  style_merge_id = Set.new(menu.select{ |m| m.dig('category', 'style_merge') }.map{ |m| m['category']['id'] })

  missing_classes = Set.new
  pois_geojson = pois_geojson.select{ |feature|
    display = feature['properties']['display']

    (
      display &&
      feature['geometry'] && feature['geometry']['type'] &&
      (feature['geometry']['type'] != 'Point' ||
        (
          display['style_class'] &&
          !(Set.new(feature.dig('properties', 'metadata', 'category_ids') || []) & style_merge_id).empty?
        )
      )
    )
  }.collect{ |feature|
    p = feature['properties']
    id = p['metadata']['id']
    superclass, class_, subclass = p['display']['style_class']
    onto = class_ontology(superclass, class_, subclass, ontology, ontology_overwrite, p)
    if !onto && feature['geometry']['type'] == 'Point'
      missing_classes << "#{superclass}/#{class_}/#{subclass}"
      next
    end
    p = p.merge({
      id: id,
      category_ids: category_ids(p['metadata']['category_ids']),
      superclass: superclass,
      class: class_,
      subclass: subclass,
      priority: onto && onto['priority'],
      zoom: onto && onto['zoom'],
      style: onto && onto['style'],
      color_fill: p['display'] && p['display']['color_fill'],
      color_line: p['display'] && p['display']['color_line'],
      popup_fields: p['editorial'] && p['editorial']['popup_fields'] && p['editorial']['popup_fields'].to_json,
    })
    p['name:latin'] = p['name'] if p.key?('name')
    p.delete('metadata')
    p.delete('editorial')
    p.delete('display')

    {
      type: 'Feature',
      properties: p.transform_values{ |v| v && v.is_a?(Array) ? v.join(';') : v },
      geometry: feature['geometry'],
    }
  }.compact

  missing_classes.each{ |mc|
    warn "Missing #{mc}"
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
    if tracks.size != 2
      merge_tracks += tracks
      ends.delete(p)
    end
  }
  merge_tracks = merge_tracks.uniq - ends.collect{ |_p, tracks| tracks }.flatten(1)

  while ends.size > 0
    p = ends.keys[0]
    tracks = ends[p]
    ends.delete(p)

    # Merge consecutive linestring
    tracks_0 = tracks[0]
    tracks_1 = tracks[1]
    tracks[0] = tracks[0].reverse if tracks[0][-1] != p
    tracks[1] = tracks[1].reverse if tracks[1][0] != p

    merge_track = tracks[0] + tracks[1][1..-1]

    # Update ends
    if ends.include?(merge_track[0]) || ends.include?(merge_track[-1])
      ends[merge_track[0]] = ends[merge_track[0]] - [tracks_0] + [merge_track] if ends.include?(merge_track[0])
      ends[merge_track[-1]] = ends[merge_track[-1]] - [tracks_1] + [merge_track] if ends.include?(merge_track[-1])
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
      color_fill: p['display'] && p['display']['color_fill'],
      color_line: p['display'] && p['display']['color_line'],
      popup_fields: p['editorial'] && p['editorial']['popup_fields'] && p['editorial']['popup_fields'].to_json,
    })
    p['name:latin'] = p['name'] if p.key?('name')

    feature['geometry'] = gpx2geojson(feature['properties']['route:trace'])
    p.delete('route:trace')

    p.delete('metadata')
    p.delete('editorial')
    p.delete('display')

    feature['properties'] = p.transform_values{ |v| v && v.is_a?(Array) ? v.join(';') : v }
    feature
  }
end

def tippecanoe(pois_layers, features_json, features_layer, mbtiles, attribution)
  system(
    'tippecanoe --force ' +
      pois_layers.collect{ |pois_json, pois_layer|
        "--named-layer=#{pois_layer}:#{pois_json} "
      }.join(' ') + "\
      --named-layer=#{features_layer}:#{features_json} \
      --use-attribute-for-id=id \
      --convert-stringified-ids-to-numbers \
      --attribution='#{attribution}' \
      -o #{mbtiles}
  "
  )

  # TODO: limiter par zoom dans le tuiles : ne marche pas
  # -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'
end

def build(_source_id, source, config_path)
  fetcher = source['sources']['partial']['fetcher']
  data_api_url = fetcher['data_api_url']

  polygon = "#{config_path}#{_source_id}.geojson"
  setting("#{data_api_url}/settings.json", polygon)

  mbtiles = config_path + source['sources']['partial']['mbtiles']

  features_data = []
  pois_layers = source['merge_layers'].compact.collect{ |source_layer_id, source_layer|
    filter = "#{config_path}#{_source_id}-classes.json"
    m = menu("#{data_api_url}/menu.json", filter)

    ontology = JSON.parse(http_get(source['sources']['full']['ontology']['url']))
    ontology_overwrite = source['sources']['full']['ontology']['overwrite'] || {}

    puts('- fetch from API')
    pois = JSON.parse(http_get("#{data_api_url}/pois.geojson?short_description=true"))
    pois_features = pois['features']

    puts('- Convert POIs')
    pois_data, poi_features_data = pois(m, pois_features, ontology, ontology_overwrite)
    features_data += poi_features_data
    puts('- Convert Routes')
    features_data += routes(pois_features)

    pois_json = mbtiles.gsub('.mbtiles', '-pois.geojson')
    File.write(pois_json, JSON.pretty_generate({
      type: 'FeatureCollection',
      features: pois_data
    }))

    [pois_json, source_layer_id]
  }

  features_json = mbtiles.gsub('.mbtiles', '-features.geojson')
  File.write(features_json, JSON.pretty_generate({
    type: 'FeatureCollection',
    features: features_data
  }))

  attribution = fetcher['attribution']
  tippecanoe(pois_layers, features_json, 'features', mbtiles, attribution)
end


ids = ARGV

@config['sources'].select{ |id, _source| ids.empty? || ids.include?(id) }.each{ |source_id, source|
  begin
    puts(source_id)
    build(source_id, source, @config_path)
  rescue StandardError => e
    puts "Error during processing: #{$!}"
    puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
  end
}

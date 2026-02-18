#!/usr/bin/ruby

require 'rubygems'
require 'bundler'
Bundler.setup

require 'English'
require 'yaml'
require 'json'
require 'set'
require 'http'
require 'active_support/all'
require 'sentry-ruby'

if ENV['SENTRY_DSN_FETCHER']
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN_FETCHER']
    config.sample_rate = 1.0
    config.traces_sample_rate = 1.0
    config.breadcrumbs_logger = [:http_logger]
    config.include_local_variables = true
  end
end

config = ENV.fetch('CONFIG', nil)
@config = YAML.load(File.read(config), aliases: true)

@config_path = @config['server']['config_path'] || ''

def http_get(url)
  resp = HTTP.headers(@config['fetch_http_headers'] || {}).follow.get(url)
  raise resp unless resp.status.success?

  resp.body
end

def setting(url, polygon)
  setting = JSON.parse(http_get(url))
  File.write(polygon, JSON.pretty_generate(setting['polygon']['data']))
  setting
end

def menu(url, json)
  menu = JSON.parse(http_get(url))
  classes = menu.pluck('category').compact.select{ |m|
    m['style_merge'] && m['style_class']
  }.pluck('style_class').sort.uniq
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
    o = ontology.dig('group', superclass, 'group', class_, 'group', subclass)
    (o && class_ontology_select(
      o,
      ontology_overwrite.dig('group', superclass, 'group', class_, 'group', subclass),
      properties
    )) || nil
  elsif class_
    o = ontology.dig('group', superclass, 'group', class_)
    (o && class_ontology_select(
      o,
      ontology_overwrite.dig('group', superclass, 'group', class_),
      properties
    )) || nil
  else
    o = ontology.dig('group', superclass)
    (o && class_ontology_select(
      o,
      ontology_overwrite.dig('group', superclass),
      properties
    )) || nil
  end
end

def pois(menu, pois_geojson, ontology, ontology_overwrite)
  menu = menu.select{ |m| !m.dig('category', 'style_merge').nil? }
  menu_by_id = menu.index_by{ |m| m['id'] }
  category_merge_ids = Set.new(menu_by_id.keys)
  puts "    Merge #{category_merge_ids.size} categories"

  missing_classes = Set.new
  pois_geojson_size = pois_geojson.size
  pois_geojson = pois_geojson.collect{ |feature|
    geometry_type = feature.dig('geometry', 'type')
    next if geometry_type.nil?
    category_ids = feature.dig('properties', 'metadata', 'category_ids')
    next if category_ids.nil?
    next if !category_merge_ids.intersect?(category_ids)
    [geometry_type, category_ids, feature]
  }.compact
  puts "    Filtered to #{pois_geojson.size} objects from #{pois_geojson_size}"

  pois_geojson = pois_geojson.collect{ |geometry_type, category_ids, feature|
    p = feature['properties']
    id = p['metadata']['id']
    menu = menu_by_id[category_ids&.first]
    if menu.nil?
      puts "Missing menu for category_id=#{category_ids&.first} in POI id=#{id}"
      next
    end
    category = menu['category']

    if geometry_type == 'Point'
      next if category['style_class'].nil?
      superclass, class_, subclass = category['style_class']
      onto = class_ontology(superclass, class_, subclass, ontology, ontology_overwrite, p)
      if !onto
        missing_classes << [superclass, class_, subclass].compact.join('/')
        next
      end

      p = p.merge({
        id:,
        category_ids: category_ids(category_merge_ids & category_ids),
        superclass:,
        class: class_,
        subclass:,
        priority: onto['priority'],
        zoom: onto['zoom'],
        style: onto['style'],
      })
    else
      p = p.merge({
        id:,
        category_ids: category_ids(category_ids),
        color_fill: p.dig('display', 'color_fill') || category['color_fill'],
        color_line: p.dig('display', 'color_line') || category['color_line'],
        color_text: p.dig('display', 'color_text') || category['color_text'],
      })
    end

    p['name:latin'] = p['name'] if p.key?('name')
    p.delete('metadata')
    p.delete('editorial')
    p.delete('display')
    p = p.compact

    {
      type: 'Feature',
      properties: p.transform_values{ |v| v&.is_a?(Array) ? v.join(';') : v },
      geometry: feature['geometry'],
    }
  }.compact

  missing_classes.each{ |mc|
    warn "Style class not found in ontology: #{mc}"
  }

  groups = pois_geojson.group_by{ |feature|
    feature[:geometry]['type'] == 'Point'
  }

  [groups[true] || [], groups[false] || []]
end

def tippecanoe(pois_layers, features_json, features_layer, mbtiles, attributions, min_zoom, maximum_tile_bytes)
  attributions = attributions.collect{ |attribution| attribution.gsub('&copy;', '©') }
  system(
    'tippecanoe --force ' +
      pois_layers.collect{ |pois_json, pois_layer|
        "--named-layer=#{pois_layer}:#{pois_json} "
      }.join(' ') + "\
      -Z#{min_zoom} \
      --named-layer=#{features_layer}:#{features_json} \
      --use-attribute-for-id=id \
      --convert-stringified-ids-to-numbers \
      --coalesce-smallest-as-needed \
      --drop-smallest-as-needed \
      --coalesce-fraction-as-needed \
      --maximum-tile-bytes=#{maximum_tile_bytes} \
      --attribution='#{attributions.join(' ').gsub("'", "'\\\\''")}' \
      -o #{mbtiles}
  "
  )

  # TODO: limiter par zoom dans le tuiles : ne marche pas
  # -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'
end

def build(source_id, source, config_path)
  fetcher = source['sources']['partial']['fetcher']
  data_api_url = fetcher['data_api_url']

  polygon = "#{config_path}#{source_id}.geojson"
  settings = setting("#{data_api_url}/settings.json", polygon)
  attributions = settings['attributions'] || []

  mbtiles = config_path + source['sources']['partial']['mbtiles']

  features_data = []
  pois_layers = source['merge_layers'].compact.collect{ |source_layer_id, _source_layer|
    filter = "#{config_path}#{source_id}-classes.json"
    m = menu("#{data_api_url}/menu.json", filter)

    ontology = JSON.parse(http_get(source['sources']['full']['ontology']['url']))
    ontology_overwrite = source['sources']['full']['ontology']['overwrite'] || {}

    puts('- fetch from API')
    pois = JSON.parse(http_get("#{data_api_url}/pois.geojson?short_description=true"))
    pois_features = pois['features']

    puts('- Convert POIs')
    pois_data, poi_features_data = pois(m, pois_features, ontology, ontology_overwrite)
    features_data += poi_features_data

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

  maximum_tile_bytes = source.dig('output', 'maximum_tile_bytes')&.to_i || 500_000
  min_zoom = source.dig('output', 'min_zoom')&.to_i || 9
  tippecanoe(pois_layers, features_json, 'features', mbtiles, attributions, min_zoom, maximum_tile_bytes)
end


ids = ARGV

@config['sources'].select{ |id, _source| ids.empty? || ids.include?(id) }.each{ |source_id, source|
  begin
    puts(source_id)
    build(source_id, source, @config_path)
  rescue StandardError => e
    Sentry.capture_exception(e)
    puts "Error during processing: #{$ERROR_INFO}"
    puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
  end
}

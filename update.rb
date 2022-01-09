#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'set'
require 'deep_merge'
require 'webcache'


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


def pois(pois_geojson, geojson, ontology)
    missing_classes = Set.new()
    pois_geojson = pois_geojson.select{ |feature|
        display = feature['properties']['display']
        display && display['tourism_style_class'] && display['tourism_style_class'] != ''
    }.collect{ |feature|
        p = feature['properties']
        id = p['metadata']['id']
        superclass, class_, subclass = p['display']['tourism_style_class']
        begin
            onto = subclass ? ontology['superclass'][superclass]['class'][class_]['subclass'][subclass] : class_ ? ontology['superclass'][superclass]['class'][class_] : ontology['superclass'][superclass]
            raise if !onto
        rescue
            missing_classes << "#{superclass}/#{class_}/#{subclass}"
            next
        end
        p.merge!({
            id: id,
            superclass: superclass,
            'class': class_,
            subclass: subclass,
            priority: onto['priority'],
            zoom: onto['zoom'],
            style: onto['style'],
        })
        p['name:latin'] = p['name'] if p.key?('name')
        p.delete('metadata')
        p.delete('editorial')
        p.delete('display')

        feature['properties'] = Hash[p.collect{ |k, v| [k, v && v.kind_of?(Array) ? v.join(';') : v] }]
        feature
    }

    missing_classes.each{ |mc|
        STDERR.puts "Missing #{mc}"
    }

    pois_geojson = {
        type: 'FeatureCollection',
        features: pois_geojson,
    }
    File.write(geojson, JSON.pretty_generate(pois_geojson))
end


def tippecanoe(pois_json, mbtiles, layer, attribution)
    system("""
        tippecanoe --force \
            --layer=#{layer} \
            --use-attribute-for-id=id \
            --convert-stringified-ids-to-numbers \
            --attribution='#{attribution}' \
            -o #{mbtiles} #{pois_json}
    """)

    # TODO limiter par zoom dans le tuiles : ne marche pas
    # -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'
end


config = YAML.load(File.read(ARGV[0]))
config['styles'].each{ |style_id, style|
    fetcher = style['sources']['partial']['fetcher']
    data_api_url = fetcher['data_api_url']

    polygon = style['merge_layer']['polygon']
    setting(data_api_url, polygon)

    classes = style['merge_layer']['classes']
    menu(data_api_url + '/menu', classes)

    ontology = JSON.parse(@download_cache.get(style['sources']['full']['ontology']['url']).content)
    ontology_overwrite = style['sources']['full']['ontology']['data'] || {}
    ontology.deep_merge!(ontology_overwrite)

    pois = JSON.parse(@download_cache.get(data_api_url + '/pois').content)
    pois_features = pois['features']

    mbtiles = style['sources']['partial']['mbtiles']

    pois_json = mbtiles.gsub('.mbtiles', '-pois.geojson')
    pois(pois_features, pois_json, ontology)

    layer = style['merge_layer']['layer']
    attribution = fetcher['attribution']
    tippecanoe(pois_json, mbtiles, layer, attribution)
}

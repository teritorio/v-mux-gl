#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'open-uri'
require 'set'


@ontology = JSON.parse(URI.parse('https://vecto.teritorio.xyz/data/teritorio-ontology-latest.json').read)


def menu(url, json)
    menu = JSON.parse(URI.parse(url).read)
    classes = menu.collect{|key, m|
        m['metadata']
    }.select{ |m|
        m['tourism_style_merge']
    }.collect{ |m|
        m['tourism_style_class']
    }.sort.uniq
    File.write(json, JSON.pretty_generate(classes))
end


def posts(url, geojson)
    allposts = JSON.parse(URI.parse(url).read)
    allposts_geojson = allposts.collect{ |key, post| post[0]['FeaturesCollection']['features'] }.flatten(1)

    missing_classes = Set.new()
    allposts_geojson = allposts_geojson.select{ |feature|
        metadata = feature['properties']['metadata']
        metadata && metadata['tourism_style_class'] && metadata['tourism_style_class'] != '' #&& metadata['tourism_style_merge']
    }.collect{ |feature|
        p = feature['properties']
        pid = p['metadata']['PID']
        superclass, class_, subclass = p['metadata']['tourism_style_class']
        begin
            onto = subclass ? @ontology['superclass'][superclass]['class'][class_]['subclass'][subclass] : class_ ? @ontology['superclass'][superclass]['class'][class_] : @ontology['superclass'][superclass]
            raise if !onto
        rescue
            missing_classes << "#{superclass}/#{class_}/#{subclass}"
            next
        end
        p.merge!({
            PID: pid,
            superclass: superclass,
            'class': class_,
            subclass: subclass,
            priority: onto['priority'],
            zoom: onto['zoom'],
            style: onto['style'],
        })
        p['name:latin'] = p['name'] if p.key?('name')
        p.delete('post_title')
        p.delete('metadata')

        feature.delete('wp_tags')
        feature.delete('covid19_fields')
        feature
    }

    missing_classes.each{ |mc|
        STDERR.puts "Missing #{mc}"
    }

    allposts_geojson = {
        type: 'FeatureCollection',
        features: allposts_geojson,
    }
    File.write(geojson, JSON.pretty_generate(allposts_geojson))
end


def tippecanoe(geojson, mbtiles, layer, attribution)
    system("""
        tippecanoe --force \
            --layer=#{layer} \
            --use-attribute-for-id=PID \
            --convert-stringified-ids-to-numbers \
            --attribution='#{attribution}' \
            -o #{mbtiles} #{geojson}
    """)

    # TODO limiter par zoom dans le tuiles : ne marche pas
    # -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'
end


config = YAML.load(File.read(ARGV[0]))
config['styles'].each{ |style_id, style|
    fetcher = style['sources']['partial']['fetcher']
    data_api_url = fetcher['data_api_url']

    classes = style['merge_layer']['classes']
    menu(data_api_url + '/api.teritorio/geodata/v1/menu', classes)

    mbtiles = style['sources']['partial']['mbtiles']
    layer = style['merge_layer']['layer']
    attribution = fetcher['attribution']
    posts(data_api_url + '/api.teritorio/geodata/v1/allposts', mbtiles + '.geojson')
    tippecanoe(mbtiles + '.geojson', mbtiles, layer, attribution)
}

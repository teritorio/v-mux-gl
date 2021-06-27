#!/usr/bin/ruby

require 'json'
require 'open-uri'


ontology = JSON.parse(URI.parse('https://vecto.teritorio.xyz/data/teritorio-ontology-latest.json').read)

geojson = JSON.parse($stdin.read)



geojson['features'] = geojson['features'].select{ |feature|
    metadata = feature['properties']['metadata']
    metadata && metadata['tourism_style_class'] && metadata['tourism_style_class'] != '' #&& metadata['tourism_style_merge']
}.collect{ |feature|
    p = feature['properties']
    pid = p['metadata']['PID']
    superclass, class_, subclass = p['metadata']['tourism_style_class']
    begin
        onto = subclass ? ontology['superclass'][superclass]['class'][class_]['subclass'][subclass] : class_ ? ontology['superclass'][superclass]['class'][class_] : ontology['superclass'][superclass]
        raise if !onto
    rescue
        STDERR.puts "Mssing #{superclass}/#{class_}/#{subclass}"
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
    feature
}

puts JSON.dump(geojson)

#!/bin/bash

API=$1

curl $API/api.teritorio/geodata/v1/allposts > allposts.json


# Make valid GeoJSON
cat allposts.json | jq '{type: "FeatureCollection", features: [.[][0].FeaturesCollection.features[]] }' > allposts.geojson

ruby edit.rb < allposts.geojson 2> >(sort | uniq -c >&2) | jq . > all.geojson

tippecanoe --force \
    --layer=poi_tourism \
    --use-attribute-for-id=PID \
    --convert-stringified-ids-to-numbers \
    --attribution='&copy; <a href="https://www.sirtaqui-aquitaine.com/les-donnees-du-sirtaqui/">Sirtaqui</a>' \
    -o all.mbtiles all.geojson

curl $API/api.teritorio/geodata/v1/menu | \
    jq -c '[.[].metadata | select(.tourism_style_merge) | .tourism_style_class] | sort | unique' > classes.json

# TODO limiter par zoom dans le tuiles : ne marche pas
# -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'

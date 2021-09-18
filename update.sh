#!/bin/bash

API=$1
DIR=$2

curl $API/api.teritorio/geodata/v1/allposts > $DIR/allposts.json


# Make valid GeoJSON
cat $DIR/allposts.json | \
    jq '{type: "FeatureCollection", features: [.[][0].FeaturesCollection.features[]] }' \
    > $DIR/allposts.geojson

ruby edit.rb < $DIR/allposts.geojson 2> >(sort | uniq -c >&2) | jq . > $DIR/all.geojson

curl $API/api.teritorio/geodata/v1/menu | \
    jq -c '[.[].metadata | select(.tourism_style_merge) | .tourism_style_class] | sort | unique' > $DIR/classes.json


tippecanoe --force \
    --layer=poi_tourism \
    --use-attribute-for-id=PID \
    --convert-stringified-ids-to-numbers \
    --attribution='&copy; <a href="https://www.sirtaqui-aquitaine.com/les-donnees-du-sirtaqui/">Sirtaqui</a>' \
    -o $DIR/all.mbtiles $DIR/all.geojson

# TODO limiter par zoom dans le tuiles : ne marche pas
# -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'

#!/usr/bin/bash

API=$1

curl $API > allposts.json


# Make valid GeoJSON
cat allposts.json | jq '{type: "FeatureCollection", features: [.[][0].FeaturesCollection.features[]] }' > allposts.geojson

ruby edit.rb < allposts.geojson 2> >(sort | uniq -c >&2) | jq . > all.geojson

tippecanoe --force \
    --layer=poi_tourism \
    --use-attribute-for-id=PID \
    --convert-stringified-ids-to-numbers \
    --attribution='&copy; <a href="https://www.sirtaqui-aquitaine.com/les-donnees-du-sirtaqui/">Sirtaqui</a>' \
    -o all.mbtiles all.geojson


cat allposts.geojson | jq -c '.features[].properties.metadata | select(.tourism_style_merge==true) | .tourism_style_class' | sort | uniq

# TODO limiter par zoom dans le tuiles : ne marche pas
# -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'

#!/usr/bin/bash

curl https://cdt40.carto.guide/api.teritorio/geodata/v1/allposts > allposts.json


# Make valid GeoJSON
cat allposts.json | jq '{type: "FeatureCollection", features: [.[][0].FeaturesCollection.features[]] }' > allposts.geojson

ruby edit.rb < allposts.geojson | jq . > all.geojson 2> >(sort | uniq -c)

tippecanoe --force \
    --layer=poi_tourism \
    --use-attribute-for-id=PID \
    --convert-stringified-ids-to-numbers \
    --attribution='&copy; <a href="https://www.sirtaqui-aquitaine.com/les-donnees-du-sirtaqui/">Sirtaqui</a>' \
    -o all.mbtiles all.geojson


cat all.geojson | jq -c '.features[].properties.metadata | select(.tourism_style_merge==true) | .tourism_style_class' | sort | uniq

# TODO limiter par zoom dans le tuiles : ne marche pas
# -j '{ "*": [  ">=", "$zoom", ["get", "zoom"] ] }'

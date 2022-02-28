vt_merge_proxy_server

# Build
```
docker-compose -f docker-compose.yaml -f docker-compose-tools.yaml build
```

# Configuration

`config.yaml`

```yaml
sources:
    foo:
        key: fi787or6ej8famrejfffp
        polygon: dax.geojson

        sources:
            full:
                tilejson_url: https://vecto-dev.teritorio.xyz/data/teritorio-dev.json
                tile_url: http://localhost:3000
            partial:
                mbtiles: restaurent-20200819.mbtiles

        merge_layers:
            poi_tourism:
                fields: [superclass, class, subclass]
                classes: classes.json
            features_tourism:

        output:
            min_zoom: 14

        styles:
            teritorio-tourism-0.9:
                url: https://vecto.teritorio.xyz/styles/teritorio-tourism-0.9/style.json
                merged_source: openmaptiles

server:
    public_base_path:
    public_tile_url_prefixes: []
```


# Initialize data
Setup configuration in `data` and fetch data:
```
docker-compose -f docker-compose-tools.yaml run --rm vt_merge_proxy_fetcher
```

# Run
```
docker-compose up -d
```

Fill the tiles cache in nginx:
```
docker-compose -f docker-compose-tools.yaml run --rm expire
```


# Data update

Get and switch to new data:
```
docker-compose -f docker-compose-tools.yaml run --rm vt_merge_proxy_fetcher
docker-compose restart
```

Update the tiles cache in nginx:
```
docker-compose -f docker-compose-tools.yaml run --rm expire
```


# Serve

Under reverse proxy HTTP header `Host` should contains the original value.
Header `Forwarded` should also properly set. See https://www.nginx.com/resources/wiki/start/topics/examples/forwarded/

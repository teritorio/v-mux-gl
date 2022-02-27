# vt_merge_proxy

Vector tiles proxy to merge datasources


Install
```
pip install -r requirements.txt
```

Run with a ASGI compatible server. Eg uvicorn:
```
uvicorn --workers 4 vt_merge_proxy.server:app
```
A cache must me be provided on top to improve performance.


Alternatively, just use the provided docker-compose configuration.

# Dev

Install
```
pip install -r requirements.txt -r requirements-dev.txt -r requirements-test.txt
```

Run
```
CONFIG=config.yaml uvicorn vt_merge_proxy.server:app --reload
```

Before commit check:
```
isort vt_merge_proxy/
black vt_merge_proxy/
flake8 vt_merge_proxy/
mypy vt_merge_proxy/
```

# Configuration

`config.yaml`

```yaml
sources:
    default:
        hosts:
            - localhost
            - 127.0.0.1
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

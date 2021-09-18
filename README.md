Install
```
apt install ruby tippecanoe jq
```

Run
```
./update.sh https://cdt40.carto.guide
```

Using Docker
```
docker build -t vt_merge_proxy_fetcher .
docker run --rm -v `pwd`:/data vt_merge_proxy_fetcher bash update.sh https://cdt40.carto.guide /data
```

Output `all.mbtiles` and `classes.json` files.

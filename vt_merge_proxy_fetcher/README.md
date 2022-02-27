Install
```
apt install ruby tippecanoe
```

Run
```
ruby ./update.rb ../data/config.yaml
```

Using Docker
```
docker build -t vt_merge_proxy_fetcher .
docker run --rm -v `pwd`:/data vt_merge_proxy_fetcher bash ./update.rb /data/config.yaml
```

Output `*.mbtiles` and `*.classes.json` files.

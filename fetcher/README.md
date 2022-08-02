Install
```
apt install ruby tippecanoe
```

Run
```
ruby ./fetcher.rb ../data/config.yaml
```

Using Docker
```
docker build -t fetcher .
docker run --rm -v `pwd`:/data fetcher bash ./fetcher.rb /data/config.yaml
```

Output `*.mbtiles` and `*.classes.json` files.

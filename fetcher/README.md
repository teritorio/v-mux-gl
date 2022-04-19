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
docker build -t fetcher .
docker run --rm -v `pwd`:/data fetcher bash ./update.rb /data/config.yaml
```

Output `*.mbtiles` and `*.classes.json` files.

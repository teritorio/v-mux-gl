vt_merge_proxy_server

# Build
```
docker-compose -f docker-compose.yaml -f docker-compose-tools.yaml build
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
Header `Forwarded` should also properly set.

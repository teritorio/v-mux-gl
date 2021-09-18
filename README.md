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

# Data update

Get and switch to new data:
```
docker-compose -f docker-compose-tools.yaml run --rm vt_merge_proxy_fetcher
docker-compose restart
```

Fill or update tiles in nginx cache:
```
docker-compose -f docker-compose-tools.yaml run --rm expire
```

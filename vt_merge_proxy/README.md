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

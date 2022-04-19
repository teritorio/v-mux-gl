# merge_proxy

Vector tiles proxy to merge datasources


Install
```
pip install -r requirements.txt
```

Run with a ASGI compatible server. Eg uvicorn:
```
uvicorn --workers 4 merge_proxy.server:app
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
CONFIG=config.yaml uvicorn merge_proxy.server:app --reload
```

Before commit check:
```
isort merge_proxy/
black merge_proxy/
flake8 merge_proxy/
mypy merge_proxy/

python -m pytest --cov=package_name --cov-report term --cov-report xml --cov-config .coveragerc --junitxml=merge_proxy/testresults.xml
```

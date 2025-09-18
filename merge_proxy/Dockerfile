FROM python:3.12-alpine3.20

RUN apk update && apk add curl git gcc geos-dev proj-util proj-dev musl-dev

WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt
COPY . .
CMD ./entrypoint.sh
EXPOSE 8000

HEALTHCHECK \
    --start-interval=1s \
    --start-period=30s \
    --interval=30s \
    --timeout=20s \
    --retries=5 \
    CMD curl --fail http://localhost:8000 || exit 1

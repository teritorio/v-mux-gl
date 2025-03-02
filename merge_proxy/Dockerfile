FROM python:3.12-alpine3.20

RUN apk update && apk add curl git gcc geos-dev proj-util proj-dev musl-dev

WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt
COPY . .
CMD ./entrypoint.sh
EXPOSE 8000

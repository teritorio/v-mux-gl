FROM python:3.9-alpine

RUN apk add --no-cache bash

ADD requirements.txt .
RUN pip install -r requirements.txt

ADD get_tiles.py .

FROM alpine:3.13

ARG TIPPECANOE_RELEASE="1.36.0"

RUN apk add --no-cache bash curl jq ruby ruby-json

RUN apk add --no-cache git g++ make libgcc libstdc++ sqlite-libs sqlite-dev zlib-dev && \
    git clone https://github.com/mapbox/tippecanoe.git tippecanoe && \
    cd tippecanoe && \
    git checkout tags/$TIPPECANOE_RELEASE && \
    make && \
    make install && \
    cd / && \
    rm -rf /tippecanoe

ADD edit.rb .
ADD update.sh .

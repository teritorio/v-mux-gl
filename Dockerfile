FROM alpine:3.14

ARG TIPPECANOE_RELEASE="1.36.0"

RUN apk add --no-cache bash curl jq ruby ruby-json

RUN apk add --no-cache git g++ make libgcc libstdc++ sqlite-libs sqlite-dev zlib-dev bash \
 && cd /root \
 && git clone https://github.com/mapbox/tippecanoe.git tippecanoe \
 && cd tippecanoe \
 && git checkout tags/$TIPPECANOE_RELEASE \
 && cd /root/tippecanoe \
 && make \
 && make install \
 && cd /root \
 && rm -rf /root/tippecanoe \
 && apk del git g++ make sqlite-dev

ADD edit.rb .
ADD update.sh .

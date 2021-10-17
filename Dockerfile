FROM alpine:3.13

ARG TIPPECANOE_RELEASE="1.36.0"

RUN apk add --no-cache bash curl ruby ruby-json && \
    gem install yaml deep_merge

RUN apk add --no-cache git g++ make libgcc libstdc++ sqlite-libs sqlite-dev zlib-dev && \
    git clone https://github.com/mapbox/tippecanoe.git tippecanoe && \
    cd tippecanoe && \
    git checkout tags/$TIPPECANOE_RELEASE && \
    make && \
    make install && \
    cd / && \
    rm -rf /tippecanoe

ADD update.rb .

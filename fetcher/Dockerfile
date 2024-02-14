FROM alpine:3.18

ARG TIPPECANOE_RELEASE="2.44.0"

RUN apk add --no-cache bash git g++ make libgcc libstdc++ sqlite-libs sqlite-dev zlib-dev && \
    git clone https://github.com/felt/tippecanoe.git tippecanoe && \
    cd tippecanoe && \
    git checkout tags/$TIPPECANOE_RELEASE && \
    make && \
    make install && \
    cd / && \
    rm -rf /tippecanoe
RUN apk add --no-cache --virtual build-dependencies build-base bash curl ruby ruby-dev ruby-bundler ruby-json libffi-dev

ADD Gemfile .
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD fetcher.rb .

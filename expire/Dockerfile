FROM alpine:3.13

RUN apk add --no-cache bash ruby ruby-json && \
    gem install yaml

ADD get_tiles.rb .

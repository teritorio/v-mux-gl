FROM ruby:3.1-alpine

RUN apk add --no-cache --virtual build-dependencies build-base ruby-dev ruby-json

ADD Gemfile .
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD get_tiles.rb .

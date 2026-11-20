FROM ruby:3.4.13-alpine

RUN apk add --no-cache --virtual build-dependencies build-base ruby-dev

ADD Gemfile .
RUN bundle config --global silence_root_warning 1
RUN bundle install

ADD get_tiles.rb .

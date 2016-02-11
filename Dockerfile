FROM alpine:3.3
MAINTAINER Anton Bakai <me@inso.im>

RUN apk update -q && apk add -q \
    build-base \
    sqlite-dev \
    libffi-dev \
    ruby \
    ruby-dev \
    ruby-bigdecimal \
    ruby-io-console \
    nodejs \
 && rm -f /var/cache/apk/*
RUN gem install bundler --no-ri --no-rdoc

ADD . /app
WORKDIR /app

RUN bundle install
RUN bundle exec rake assets

EXPOSE 1025
EXPOSE 1080

ENTRYPOINT ["bundle", "exec", "mailcatcher", "-f"]
CMD ["--ip", "0.0.0.0"]

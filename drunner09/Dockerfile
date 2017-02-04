# Rocketchat
FROM debian

RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y wget \
 && rm -rf /var/lib/apt/lists/*

COPY ["./usrlocalbin","/usr/local/bin"]
RUN chmod a+x /usr/local/bin/*

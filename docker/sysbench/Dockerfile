FROM ubuntu:bionic as builder
USER root
RUN apt-get update && apt -y install \
    git \
    make \
    automake \
    libtool \
    pkg-config \
    libaio-dev \
    libmysqlclient-dev \
    libssl-dev \
    libpq-dev
RUN mkdir -p /tmp/build
WORKDIR /tmp/build
RUN set -x \
 && git clone https://github.com/akopytov/sysbench.git -b 1.0.20 . \
 && ./autogen.sh \
 && ./configure --with-pgsql \
 && make -j \
 && make install

FROM ubuntu:bionic
USER root
RUN apt-get update && apt -y install \
    libaio-dev \
    libmysqlclient-dev \
    libssl-dev \
    libpq-dev
COPY --from=builder /usr/local/bin/sysbench /usr/local/bin/sysbench
COPY --from=builder /usr/local/share/sysbench /usr/local/share/sysbench
COPY --from=builder /usr/local/share/doc/sysbench /usr/local/share/doc/sysbench

COPY ./loop-forever.sh /bin/loop-forever.sh

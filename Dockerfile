FROM martenseemann/quic-network-simulator-endpoint:latest AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -qy mercurial build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev curl git cmake ninja-build gnutls-bin iptables libasan5

RUN useradd nginx

COPY --from=golang:latest /usr/local/go/ /usr/local/go/
ENV PATH="/usr/local/go/bin:${PATH}"

RUN git clone --depth=1 https://github.com/google/boringssl.git

RUN  cd boringssl  && \
  mkdir build && \
  cd build && \
  cmake -GNinja -DCMAKE_BUILD_TYPE=release -DBUILD_SHARED_LIBS=1 .. && \
  ninja 

RUN hg clone http://hg.nginx.org/nginx

RUN cd nginx && \
    ./auto/configure --prefix=/etc/nginx \
    --build=$(hg tip | head -n 1 | awk '{ print $2 }') \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-debug \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-cc-opt='-I/boringssl/include -O0 -fno-common -fno-omit-frame-pointer -DNGX_QUIC_DRAFT_VERSION=29 -DNGX_HTTP_V3_HQ=1 -ggdb -fsanitize=address' \
    --with-ld-opt='-L/boringssl/build/ssl -L/boringssl/build/crypto -fsanitize=address'

RUN cd nginx && make -j$(nproc)
RUN cd nginx && make install

FROM martenseemann/quic-network-simulator-endpoint:latest

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -qy libasan5

COPY --from=builder /usr/sbin/nginx /usr/sbin/
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /boringssl/build/ssl/libssl.so* /boringssl/build/crypto/libcrypto.so* /lib/x86_64-linux-gnu

RUN ldd /usr/sbin/nginx
RUN nginx -V

RUN useradd nginx
RUN mkdir -p /var/cache/nginx /var/log/nginx/

COPY nginx.conf nginx.conf.retry nginx.conf.http3 nginx.conf.nodebug /etc/nginx/

COPY run_endpoint.sh .
RUN chmod +x run_endpoint.sh

EXPOSE 443/udp
EXPOSE 443/tcp

ENTRYPOINT [ "./run_endpoint.sh" ]

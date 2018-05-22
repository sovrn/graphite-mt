FROM alpine

# add permanent dependencies
RUN apk --no-cache add \
	ca-certificates \
	py2-cairo \
	py2-pip \
	py2-gunicorn

# add transient dependencies
RUN apk --no-cache --virtual build-deps add \
	alpine-sdk \
	go \
	libffi-dev \
	py2-cairo-dev \
	python2-dev

# build graphite-web
RUN pip install --no-binary=:all: https://github.com/graphite-project/graphite-web/tarball/master
RUN cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi
RUN find /opt/graphite/webapp ! -perm -a+r -exec chmod a+r {} \;
RUN PYTHONPATH=/opt/graphite/webapp django-admin collectstatic --noinput --settings=graphite.settings
RUN PYTHONPATH=/opt/graphite/webapp django-admin migrate --settings=graphite.settings --run-syncd
RUN mkdir -vp /opt/graphite/run
RUN ln -sv /opt/graphite/webapp/content /opt/graphite/webapp/static
RUN addgroup graphite
RUN adduser -DHh /opt/graphite -s /bin/false -G graphite graphite
RUN chown -R graphite:graphite /opt/graphite

# install caddy
RUN wget -O- 'https://caddyserver.com/download/linux/amd64?plugins=http.forwardproxy,http.webdav&license=personal'\
    | tar --no-same-owner -xzC /usr/bin/ caddy

# install graphite-web-proxy
RUN GOPATH=/usr go get github.com/raintank/graphite-web-proxy

# remove transient build dependencies
RUN apk --no-cache del build-deps

# remove extraneous files
RUN rm -rf \
	/usr/src \
	/usr/doc
RUN find / -name "*.pyc" -delete

# add config files
ADD root /

# expose ports
EXPOSE 80
EXPOSE 8080
EXPOSE 8181

# set up environment variables
ENV \
	TSDB_KEY= \
	TSDB_URL= \
	GUNICORN_WORKERS=4 \
	GRAPHITE_CLUSTER_SERVERS=127.0.0.1:8181

# check api key validity as health check
HEALTHCHECK --interval=5m --timeout=10s --start-period=10s --retries=3 CMD curl https://grafana.com/api/api-keys/check -d "token=${TSDB_KEY}"

# start services, using source to avoid an extra child process
CMD source /run.sh

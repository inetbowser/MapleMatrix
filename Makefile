# Set a name/version number for image building
IMGNAME = maplematrix
VERSION = 1.0
ROOT    = $(shell pwd)# req'd if you're running w/ sudo since PWD will be wrong

.PHONY: all build shell generateCA prepCertForAndroid

all: build run

# Build the image
build:
	docker build . -t $(IMGNAME):$(VERSION) && echo Buildname: $(IMGNAME):$(VERSION)

# Run the image in a new container
run:
	#TODO change i to d when we're sure...
	docker run \
		-i \
		-t \
		--net host \
		--privileged \
		--hostname $(IMGNAME) \
		--name $(IMGNAME)_run \
		--env-file basic-env \
		-v $(ROOT)/data:/root/data:consistent \
		-v $(ROOT)/scripts:/root/scripts:consistent \
		--rm \
		$(IMGNAME):$(VERSION)

# Test the image in a new container by going interactive just before the
# entrypoint script is called
shell:
	docker run \
		-i \
		-t \
		--net host \
		--privileged \
		--hostname $(IMGNAME) \
		--name $(IMGNAME)_shell \
		--env-file basic-env \
		-v $(ROOT)/data:/root/data:consistent \
		-v $(ROOT)/scripts:/root/scripts:consistent \
		--entrypoint=/bin/bash \
		--rm \
		$(IMGNAME):$(VERSION)

# Make cert
# https://www.digitalocean.com/community/tutorials/how-to-create-a-self-signed-ssl-certificate-for-nginx-in-ubuntu-16-04
#
# alt cmd: openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout privateKey.key -out certificate.crt
generateCA:
	@openssl genrsa -out fake_ca/mitmproxy-ca.key 4096
	@openssl req -new -sha1 -x509 -days 365 -subj '/C=US/ST=Florida/L=Miami/O=Cool IT Company/OU=ITDept/CN=my.domain/emailAddress=hostmaster@my.domain' -key fake_ca/mitmproxy-ca.key -out fake_ca/mitmproxy-ca.crt
	@cat fake_ca/mitmproxy-ca.key fake_ca/mitmproxy-ca.crt > fake_ca/mitmproxy-ca.pem
	@openssl x509 -in fake_ca/mitmproxy-ca.pem -out fake_ca/mitmproxy-ca.der -outform DER

# Prep the cert for use in the android system store, based on:
# 	https://stackoverflow.com/questions/44942851/install-user-certificate-via-adb
#
# You can send the cert to the device with something like:
# 	adb push $cert_name /system/etc/security/cacerts/
CERT_HASH = $(shell openssl x509 -inform PEM -subject_hash_old -in fake_ca/mitmproxy-ca.pem | head -1)
CERT_NAME = $(CERT_HASH).0
prepCertForAndroid:
	@cat fake_ca/mitmproxy-ca.crt > fake_ca/$(CERT_NAME)
	@openssl x509 -inform PEM -text -in fake_ca/mitmproxy-ca.pem -noout >> fake_ca/$(CERT_NAME)




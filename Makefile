BINARIES=bin/greeter

IMAGE=containers.trusch.io/examples/greeter:latest
BASE_IMAGE=gcr.io/distroless/base:latest

BUILD_IMAGE=containers.trusch.io/examples/greeter-builder:latest
BASE_BUILD_IMAGE=golang:1.14
PROTOC_VERSION=3.12.3
PROTOC_GEN_GO_VERSION=v1.4.2
PROTOC_GEN_GO_GRPC_VERSION=38aafd89f814 # will be in v1.31.0, actually its already in v1.30.0 but modules are not working as expected

COMMIT=$(shell git log --format="%H" -n 1)
VERSION=$(shell git describe)

default: image

# rebuild and run the server
run: image
	podman run --rm -p 3001:3001 -p 8080:8080 $(IMAGE) /bin/greeter serve

# put binaries into image
image: .image
.image: $(BINARIES) Makefile
	$(eval ID=$(shell buildah from $(BASE_IMAGE)))
	buildah copy $(ID) ./bin/* /bin/
	buildah commit $(ID) $(IMAGE)
	buildah rm $(ID)
	touch .image

# build binaries
bin/%: $(shell find ./ -name "*.go") .buildimage
	podman run \
		--rm \
		-v ./:/app \
		-w /app \
		-v go-build-cache:/root/.cache/go-build \
		-v go-mod-cache:/go/pkg/mod $(BUILD_IMAGE) \
			go build -v -o $@ -ldflags "-X github.com/trusch/grpc-service-stub/cmd/greeter/cmd.Version=$(VERSION) -X github.com/trusch/grpc-service-stub/cmd/greeter/cmd.Commit=$(COMMIT)" cmd/$(shell basename $@)/main.go

# compile protobuf files
pkg/protobuf/%.pb.go: pkg/protobuf/%.proto .buildimage
	podman run \
		--rm \
		-v ./:/app \
		-w /app/$(shell dirname $@) $(BUILD_IMAGE) \
			/usr/local/bin/protoc \
				--go_out=paths=source_relative:. \
				--go-grpc_out=paths=source_relative:. \
				$(shell basename $<)

.buildimage: /tmp/protoc-download/bin
	$(eval ID=$(shell buildah from $(BASE_BUILD_IMAGE)))
	buildah copy $(ID) /tmp/protoc-download/bin /usr/local/bin
	buildah copy $(ID) /tmp/protoc-download/include /usr/local/include
	buildah config -e GO111MODULE=on $(ID)
	buildah run $(ID) go get -v github.com/golang/protobuf/protoc-gen-go@$(PROTOC_GEN_GO_VERSION)
	buildah run $(ID) go get -v google.golang.org/grpc/cmd/protoc-gen-go-grpc@$(PROTOC_GEN_GO_GRPC_VERSION)
	buildah commit $(ID) $(BUILD_IMAGE)
	buildah rm $(ID)
	touch .buildimage

/tmp/protoc-download/bin:
	-rm -rf /tmp/protoc-download
	mkdir /tmp/protoc-download
	wget -O /tmp/protoc-download/protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v$(PROTOC_VERSION)/protoc-$(PROTOC_VERSION)-linux-x86_64.zip
	cd /tmp/protoc-download && unzip protoc.zip

# cleanup
clean:
	-rm -r bin .image .buildimage /tmp/protoc-download
	-podman volume rm  go-build-cache go-mod-cache

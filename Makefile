IMAGE=containers.trusch.io/examples/greeter:latest
BASE_IMAGE=gcr.io/distroless/base:latest
BUILD_IMAGE=containers.trusch.io/examples/greeter-builder:latest
BASE_BUILD_IMAGE=golang:1.14
BINARIES=bin/greeter

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
	mkdir -p /tmp/go-build-cache /tmp/go-pkg-cache
	podman run \
		--rm \
		-v ./:/app \
		-w /app \
		-v go-build-cache:/root/.cache/go-build \
		-v go-mod-cache:/go/pkg/mod $(BUILD_IMAGE) \
			go build -o $@ -ldflags "-X main.GitCommit=$GIT_COMMIT"  cmd/$(shell basename $@)/main.go

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

.buildimage:
	-rm -rf /tmp/protoc-download
	mkdir -p /tmp/protoc-download
	wget -O /tmp/protoc-download/protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v3.12.3/protoc-3.12.3-linux-x86_64.zip
	cd /tmp/protoc-download && unzip protoc.zip
	$(eval ID=$(shell buildah from $(BASE_BUILD_IMAGE)))
	buildah copy $(ID) /tmp/protoc-download/bin /usr/local/bin
	buildah copy $(ID) /tmp/protoc-download/include /usr/local/include
	buildah run $(ID) go get -v github.com/golang/protobuf/protoc-gen-go
	buildah run $(ID) go get -v github.com/grpc/grpc-go/cmd/protoc-gen-go-grpc
	buildah commit $(ID) $(BUILD_IMAGE)
	buildah rm $(ID)
	touch .buildimage


# cleanup
clean:
	rm -r bin .image

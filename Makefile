

K3S_VERSION      = 1.22.17-k3s1
K3D_VERSION      = 5.4.7
K3D_CLUSTER_NAME =
K3D_ARGS         = --registry-use k3d-myregistry.localhost:12345 --k3s-arg=--no-deploy=traefik@server:* --k3s-arg=--kubelet-arg=max-pods=255@server:* --k3s-arg=--egress-selector-mode=disabled@server:*
KUBECTL_VERSION  = 1.21.6

TOOLS_DIR = tools/bin

GOHOSTOS   := $(shell go env GOHOSTOS)
GOHOSTARCH := $(shell go env GOHOSTARCH)


.PHONY: k3d
k3d:
	mkdir -p tools/bin
	curl -o tools/bin/k3d -s --fail -L https://github.com/rancher/k3d/releases/download/v$(K3D_VERSION)/k3d-$(GOHOSTOS)-$(GOHOSTARCH)
	chmod a+x tools/bin/k3d

.PHONY: kubectl
kubectl:
	mkdir -p tools/bin
	curl -o tools/bin/kubectl -L --fail https://storage.googleapis.com/kubernetes-release/release/v$(KUBECTL_VERSION)/bin/$(GOHOSTOS)/$(GOHOSTARCH)/kubectl
	chmod 755 tools/bin/kubectl

.PHONY: ci/setup-k3d
ci/setup-k3d: k3d kubectl
	tools/bin/k3d registry create myregistry.localhost --port 12345
	tools/bin/k3d cluster create --wait --image=docker.io/rancher/k3s:v$(subst +,-,$(K3S_VERSION)) $(K3D_ARGS) $(K3D_CLUSTER_NAME)
	while ! tools/bin/kubectl get serviceaccount default >/dev/null; do sleep 1; done
	tools/bin/kubectl version

ci/teardown-k3d: k3d
	tools/bin/k3d cluster delete || true
	tools/bin/k3d registry delete myregistry.localhost || true
.PHONY: ci/teardown-k3d


.PHONY: load-k3d-registry
load-k3d-registry:
	docker tag test-image:latest k3d-myregistry.localhost:12345/test-image:latest
	docker push k3d-myregistry.localhost:12345/test-image:latest

.PHONY: build
build:
	docker build -f Dockerfile -t test-image:latest .
	docker save --output /tmp/test-image.tar test-image

.PHONY: load-image-tar
load-image-tar: build
	docker load --input /tmp/test-image.tar
	docker image ls -a | grep test-image

.PHONY: e2e-test
e2e-test: kubectl
	kubectl apply -f deployment.yaml
	kubectl wait --for=condition=available --timeout=60s --all deployments


.PHONY: push-image
push-image:
	docker tag test-image:latest docker.io/parsec86/test-image:$(git rev-parse --short=12 HEAD)
	docker push docker.io/parsec86/test-image:$(git rev-parse --short=12 HEAD)
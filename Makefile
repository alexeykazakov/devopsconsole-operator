# It's necessary to set this because some environments don't link sh -> bash.
SHELL := /bin/bash

include ./make/verbose.mk
.DEFAULT_GOAL := help
include ./make/help.mk
include ./make/out.mk
include ./make/find-tools.mk
include ./make/go.mk
include ./make/git.mk
include ./make/dev.mk
include ./make/format.mk
include ./make/lint.mk
include ./make/test.mk
include ./make/docker.mk

.PHONY: build
## Build the operator
build: ./out/operator

.PHONY: clean
clean:
	$(Q)-rm -rf ${V_FLAG} ./out
	$(Q)-rm -rf ${V_FLAG} ./vendor
	$(Q)-rm -rf ${V_FLAG} ./tmp
	$(Q)go clean ${X_FLAG} ./...

./vendor: Gopkg.toml Gopkg.lock
	$(Q)dep ensure ${V_FLAG} -vendor-only

./out/operator: ./vendor $(shell find . -path ./vendor -prune -o -name '*.go' -print)
	#$(Q)operator-sdk generate k8s
	$(Q)CGO_ENABLED=0 GOARCH=amd64 GOOS=linux \
		go build ${V_FLAG} \
		-ldflags "-X ${GO_PACKAGE_PATH}/cmd/manager.Commit=${GIT_COMMIT_ID} -X ${GO_PACKAGE_PATH}/cmd/manager.BuildTime=${BUILD_TIME}" \
		-o ./out/operator \
		cmd/manager/main.go

.PHONY: copy-crds
## Copy CRD files to latest OLM manifests directory
copy-crds:
	$(eval package_yaml := ./manifests/devconsole/devconsole.package.yaml)
	$(eval devconsole_version := $(shell cat $(package_yaml) | grep "currentCSV"| cut -d "." -f2- | cut -d "v" -f2 | tr -d '[:space:]'))
	$(Q)cp ./deploy/crds/*.yaml ./manifests/devconsole/$(devconsole_version)/

.PHONY: upgrade-build
upgrade-build: upgrade-csv-build
	$(eval package_yaml := ./manifests/devconsole/devconsole.package.yaml)
	$(eval devconsole_version := $(shell cat $(package_yaml) | grep "currentCSV"| cut -d "." -f2- | cut -d "v" -f2 | tr -d '[:space:]'))
	$(Q)cp ./deploy/crds/*.yaml ./manifests/devconsole/$(devconsole_version)/
	$(Q)cp ./test/upgrade/devconsole_v1alpha1_upgrade_crd.yaml ./manifests/devconsole/$(devconsole_version)/
	$(Q)sed -e "s,REPLACE_IMAGE,registry.svc.ci.openshift.org/${OPENSHIFT_BUILD_NAMESPACE}/stable:devconsole-operator," \
		-i ./manifests/devconsole/${devconsole_version}/devconsole-operator.v${devconsole_version}.clusterserviceversion.yaml
	$(Q)tar -zcvf ./out/manifests.tar.gz manifests/

.PHONY: upgrade-csv-build
upgrade-csv-build:
	$(eval package_yaml := ./manifests/devconsole/devconsole.package.yaml)
	$(eval devconsole_version := $(shell cat $(package_yaml) | grep "currentCSV"| cut -d "." -f2- | cut -d "v" -f2 | tr -d '[:space:]'))
	$(Q)cp ./deploy/crds/*.yaml ./manifests/devconsole/$(devconsole_version)/
	$(Q)sed -e "s,REPLACE_IMAGE,registry.svc.ci.openshift.org/${OPENSHIFT_BUILD_NAMESPACE}/stable:devconsole-operator," \
		-i ./manifests/devconsole/${devconsole_version}/devconsole-operator.v${devconsole_version}.clusterserviceversion.yaml
	$(Q)python3 ./test/upgrade/upgrade.py

SCRIPTS = bin/rm libexec/trash scripts/test.sh
# Linux images with GNU (Debian, whose sh is dash) and busybox (Alpine)
# tools, each run as root and as a user without a passwd entry.
DOCKER_IMAGES = debian:stable-slim alpine:latest
DOCKER_USERS = 0:0 1000:1000

.PHONY: test test-docker lint

test:
	sh scripts/test.sh

test-docker:
	@set -e; for image in $(DOCKER_IMAGES); do \
		for user in $(DOCKER_USERS); do \
			echo "== $$image as $$user"; \
			docker run --rm --user $$user -v "$(CURDIR)":/src:ro -w /src $$image sh scripts/test.sh; \
		done; \
	done

lint:
	shellcheck $(SCRIPTS)
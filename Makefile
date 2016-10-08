# Import local environment overrides
$(shell touch .env)
include .env

# Project variables
PROJECT_NAME ?= trader-dashboard
ORG_NAME ?= dockerproductionaws
REPO_NAME ?= trader-dashboard
TEST_REPO_NAME ?= trader-dashboard-dev

# Release settings
export HTTP_PORT ?= 8000

# Demo settings
DEMO_COMPOSE_FILE := docker/demo/docker-compose.yml
DEMO_PROJECT := $(REL_PROJECT)demo
DEMO_ARGS = -p $(DEMO_PROJECT) -f $(DEMO_COMPOSE_FILE) $(VERBOSE_FLAG)
DEMO_PORT_EXPR = $$(docker-compose $(DEMO_ARGS) ps -q trader-dashboard | xargs -I ID docker port ID $(HTTP_PORT))
DEMO_PORT = $$(echo $$(IFS=':' read -r -a array <<< "$(DEMO_PORT_EXPR)" && echo "$${array[1]}"))

export MARKET_DATA_ADDRESS ?= market
export DB_NAME ?= audit
export DB_USER ?= audit
export DB_PASSWORD ?= password

# Common settings
include Makefile.settings

.PHONY: version test build release clean tag login logout publish compose dcompose database save load demo all

# Prints version
version:
	@ echo $(APP_VERSION)

# Creates workflow infrastucture
init:
	${INFO} "Checking networking..."
	@ $(if $(NETWORK_ID),,docker network create --subnet=$(NETWORK_SUBNET) --gateway=$(NETWORK_GW) $(NETWORK_NAME))

# Runs unit and integration tests
# Pulls images and base images by default
# Use 'make test nopull' to disable default pull behaviour
test: init
	${INFO} "Building images..."
	@ docker-compose $(TEST_ARGS) build $(NOPULL_FLAG) test
	${INFO} "Running tests..."
	@ docker-compose $(TEST_ARGS) up test
	${CHECK} $(TEST_PROJECT) $(TEST_COMPOSE_FILE) test
	${INFO} "Removing existing artefacts..."
	@ rm -rf target
	${INFO} "Copying build artefacts..."
	@ docker cp $$(docker-compose $(TEST_ARGS) ps -q test):/app/target/. target
	${INFO} "Test complete"

# Builds release image and runs acceptance tests
release: init
	${INFO} "Pulling latest images..."
	@ $(if $(NOPULL_ARG),,docker-compose $(RELEASE_ARGS) pull test agent)
	${INFO} "Building images..."
	@ docker-compose $(RELEASE_ARGS) build $(NOPULL_FLAG) app
	${INFO} "Running acceptance tests..."
	@ docker-compose $(RELEASE_ARGS) run agent
# @ docker-compose $(RELEASE_ARGS) up test
# @ docker cp $$(docker-compose $(RELEASE_ARGS) ps -q test):/app/target/surefire-reports/. reports
# ${CHECK} $(REL_PROJECT) $(REL_COMPOSE_FILE) test
	${INFO} "Acceptance testing complete"

# Creates a Microtrader demo environment
demo: clean-demo init
	${INFO} "Pulling latest images..."
	@ $(if $(NOPULL_ARG),,docker-compose $(DEMO_ARGS) pull trader-dashboard quote-generator audit-service portfolio-service db quote-agent audit-agent)
	${INFO} "Starting quote generator..."
	@ docker-compose $(DEMO_ARGS) run quote-agent
	${INFO} "Starting audit database..."
	@ docker-compose $(DEMO_ARGS) run audit-agent
	${INFO} "Running audit migrations..."
	@ docker-compose $(DEMO_ARGS) run audit-migrate
	${INFO} "Starting audit service..."
	@ docker-compose $(DEMO_ARGS) up -d audit-service
	${INFO} "Starting portfolio service..."
	@ docker-compose $(DEMO_ARGS) up -d portfolio-service
	${INFO} "Starting trader dashboard..."
	@ docker-compose $(DEMO_ARGS) up -d trader-dashboard
	@ docker-compose $(DEMO_ARGS) run trader-agent
	${INFO} "Demo environment created"
	${INFO} "Trader dashboard is running on http://$(DOCKER_MACHINE_IP):$(DEMO_PORT)"

# Executes a full workflow
all: clean test release
	@ make tag latest $(APP_VERSION) $(GIT_HASH) $(GIT_TAG)
	@ make publish
	@ make clean

# Cleans environment
clean: clean-test clean-release clean-demo
	${INFO} "Removing dangling images..."
	@ docker images -q -f dangling=true -f label=application=$(REPO_NAME) | xargs -I ARGS docker rmi -f ARGS
	${INFO} "Clean complete"

clean%test:
	${INFO} "Destroying test environment..."
	@ docker-compose $(TEST_ARGS) down -v || true

clean%release:
	${INFO} "Destroying release environment..."
	@ docker-compose $(RELEASE_ARGS) down -v || true

clean%demo:
	${INFO} "Destroying demo environment..."
	@ docker-compose $(DEMO_ARGS) down -v || true

# 'make tag <tag> [<tag>...]' tags development and/or release image with specified tag(s)
tag: init
	${INFO} "Tagging development image with tags $(TAG_ARGS)..."
	@ $(foreach tag,$(TAG_ARGS), echo $(TEST_IMAGE_ID) | xargs -I ARG docker tag ARG $(DOCKER_REGISTRY)/$(ORG_NAME)/$(TEST_REPO_NAME):$(tag);)
	${INFO} "Tagging release image with tags $(TAG_ARGS)..."
	@ $(foreach tag,$(TAG_ARGS), echo $(IMAGE_ID) | xargs -I ARG docker tag ARG $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME):$(tag);)
	${INFO} "Tagging complete"

# Login to Docker registry
login:
	${INFO} "Logging in to Docker registry $$DOCKER_REGISTRY..."
	@ docker login -u $$DOCKER_USER -p $$DOCKER_PASSWORD $(DOCKER_REGISTRY_AUTH)
	${INFO} "Logged in to Docker registry $$DOCKER_REGISTRY"

# Logout of Docker registry
logout:
	${INFO} "Logging out of Docker registry $$DOCKER_REGISTRY..."
	@ docker logout
	${INFO} "Logged out of Docker registry $$DOCKER_REGISTRY"

# Publishes image(s) tagged using make tag commands
publish:
	${INFO} "Publishing development image $(TEST_IMAGE_ID) to $(TEST_IMAGE)..."
	@ for tag in $(TEST_REPO_EXPR); do echo $$tag | xargs -I TAG docker push TAG; done
	${INFO} "Publishing release image $(IMAGE_ID) to $(RELEASE_IMAGE)..."
	@ for tag in $(REPO_EXPR); do echo $$tag | xargs -I TAG docker push TAG; done
	${INFO} "Publish complete"

# Saves development image build cache to compressed archive.  NOTE: lbzip2 must be installed
# 	'make save' will save to current working directory.  E.g. ./<repo_name>.bz2
#   'make save /path/to/my' will save to /path/to/my.  E.g. /path/to/my/<repo_name>.bz2
#   'make save s3://bucket/path' will save to AWS S3.  E.g. s3://bucket/path/<repo_name>.bz2
save:
	${INFO} "Saving development image $(TEST_IMAGE) to $(SAVE_PATH)/$(TEST_REPO_NAME).bz2..."
	@ $(if $(SAVE_IMAGE_EXISTS),$(TEST_SAVE_CMD),${INFO} "Skipping as development image is not present...")
	${INFO} "Save complete"

# Loads development image build cache from compressed archive.  NOTE: lbzip2 must be installed
#   'make load' will load from current working directory.  E.g. ./<repo_name>.bz2
#   'make load /path/to/my' will load from /path/to/my.  E.g. /path/to/my/<repo_name>.bz2
#   'make load s3://bucket/path' will load from AWS S3.  E.g. s3://bucket/path/<repo_name>.bz2
load:
	${INFO} "Loading cached development image from $(SAVE_PATH)/$(TEST_REPO_NAME).bz2..."
	@ $(if $(TEST_LOAD_MISSING),${WARNING} "Development image is not available at $(SAVE_PATH)/$(TEST_REPO_NAME).bz2 - skipping load...",)
	@ $(if $(LOAD_IMAGE_EXISTS),${WARNING} "Development image already present - skipping load...",)
	@ $(if $(TEST_LOAD_MISSING)$(LOAD_IMAGE_EXISTS),,$(TEST_LOAD_CMD))
	${INFO} "Load complete"

# Executes docker-compose commands in release environment
#   e.g. 'make compose ps' is the equivalent of docker-compose -f path/to/dockerfile -p <project-name> ps
#   e.g. 'make compose run nginx' is the equivalent of docker-compose -f path/to/dockerfile -p <project-name> run nginx
#
# Use '--'' after make to pass flags/arguments 
#   e.g. 'make -- compose run --rm nginx' ensures the '--rm' flag is passed to docker-compose and not interpreted by make
compose: init
	${INFO} "Running docker-compose command in release environment..."
	@ docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) $(COMPOSE_ARGS)

# Executes docker-compose commands in test environment
#   e.g. 'make dcompose ps' is the equivalent of docker-compose -f path/to/dockerfile -p <project-name> ps
#   e.g. 'make dcompose run test' is the equivalent of docker-compose -f path/to/dockerfile -p <project-name> run test
#
# Use '--'' after make to pass flags/arguments 
#   e.g. 'make -- compose run --rm test' ensures the '--rm' flag is passed to docker-compose and not interpreted by make
dcompose: init
	${INFO} "Running docker-compose command in test environment..."
	@ docker-compose -p $(TEST_PROJECT) -f $(TEST_COMPOSE_FILE) $(DCOMPOSE_ARGS)

# IMPORTANT - ensures arguments are not interpreted as make targets
%:
	@:

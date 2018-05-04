DIR := $(realpath $(dir $(realpath $(MAKEFILE_LIST))))
NODE_MODULES := $(DIR)/node_modules
NODE_MODULES_META := $(DIR)/package.json $(DIR)/package-lock.json

ASSETS_DIR := $(DIR)/public/assets
ASSRETS_SRC_DIR := $(DIR)/assets

ASSETS_CSS_SRC := $(ASSRETS_SRC_DIR)/stylesheets/mailcatcher.scss
ASSETS_JS_SRC := $(ASSRETS_SRC_DIR)/javascripts/mailcatcher.coffee

ASSETS_CSS := $(ASSETS_DIR)/mailcatcher.css
ASSETS_JS := $(ASSETS_DIR)/mailcatcher.js
ASSETS_VENDOR_JS := $(ASSETS_DIR)/vendor.js


.PHONY: assets
assets: $(ASSETS_CSS) $(ASSETS_JS) $(ASSETS_VENDOR_JS)

.PHONY: a
a: assets


$(ASSETS_CSS): $(ASSETS_CSS_SRC)
	cd $(DIR) && npx gulp css

$(ASSETS_JS): $(ASSETS_JS_SRC)
	cd $(DIR) && npx gulp app-js

$(ASSETS_VENDOR_JS): $(NODE_MODULES)
	cd $(DIR) && npx gulp vendor-js


.PHONY: assets-clean
assets-clean: $(NODE_MODULES)
	rm -f $(ASSETS_CSS) $(ASSETS_JS) $(ASSETS_VENDOR_JS)

.PHONY: a-c
a-c: assets-clean


.PHONY: assets-watch
assets-watch: $(NODE_MODULES)
	cd $(DIR) && npx gulp watch

.PHONY: a-w
a-w: assets-watch


.PHONY: node-modules
node-modules: $(NODE_MODULES)

$(NODE_MODULES): $(NODE_MODULES_META)
	cd $(DIR) && npm install
	touch $@


.PHONY: run
run: $(ASSETS_CSS) $(ASSETS_JS) $(ASSETS_VENDOR_JS)
	cd $(DIR) && bundle exec bin/mailcatcher -c sample_config.yml

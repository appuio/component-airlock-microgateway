# Configure instance alias for commodore component compile
commodore_args += --alias $(instance)

.PHONY: test-espejote
test-espejote: ## Render the Espejote MR through tests/render inputs and check for drift
	bash tests/render/run.sh
	git diff --exit-code -- tests/render/expected/

.PHONY: gen-espejote
gen-espejote: ## Regenerate tests/render/expected goldens
	@bash tests/render/run.sh

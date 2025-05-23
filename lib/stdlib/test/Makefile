## %CopyrightBegin%
##
## SPDX-License-Identifier: Apache-2.0
##
## Copyright Ericsson AB 2009-2025. All Rights Reserved.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## %CopyrightEnd%

include $(ERL_TOP)/make/target.mk
include $(ERL_TOP)/make/$(TARGET)/otp.mk

# ----------------------------------------------------
# Target Specs
# ----------------------------------------------------

MODULES= \
	array_SUITE \
	argparse_SUITE \
	base64_SUITE \
	base64_property_test_SUITE \
	beam_lib_SUITE \
	binary_module_SUITE \
	binary_property_test_SUITE \
	binref \
	c_SUITE \
	calendar_SUITE \
	calendar_prop_SUITE \
	dets_SUITE \
	dict_SUITE \
	dict_test_lib \
	digraph_SUITE \
	digraph_utils_SUITE \
	dummy1_h \
	dummy_h \
	dummy_via \
	edlin_expand_SUITE \
	edlin_context_SUITE \
	epp_SUITE \
	erl_anno_SUITE \
	erl_eval_SUITE \
	erl_expand_records_SUITE \
	erl_internal_SUITE \
	erl_lint_SUITE \
	erl_pp_SUITE \
	erl_scan_SUITE \
	error_info_lib \
	error_logger_h_SUITE \
	escript_SUITE \
	ets_property_test_SUITE \
	ets_SUITE \
	ets_tough_SUITE \
	filelib_SUITE \
	file_sorter_SUITE \
	filename_SUITE \
	fixtable_SUITE \
	format_SUITE \
	gb_sets_property_test_SUITE \
	gen_event_SUITE \
	gen_fsm_SUITE \
	gen_server_SUITE \
	gen_statem_SUITE \
	id_transform_SUITE \
	io_SUITE \
	io_proto_SUITE \
	json_SUITE \
	lists_SUITE \
	lists_property_test_SUITE \
	log_mf_h_SUITE \
	math_SUITE \
	ms_transform_SUITE \
	peer_SUITE \
	pool_SUITE \
	proc_lib_SUITE \
	proplists_SUITE \
	qlc_SUITE \
	queue_SUITE \
	queue_property_test_SUITE \
	rand_SUITE \
	random_SUITE \
	re_SUITE \
	run_pcre_tests \
	run_old_pcre1_tests \
	re_testoutput1_replacement_test \
	re_testoutput1_split_test \
	slave_SUITE \
	sets_SUITE \
	sets_property_test_SUITE \
	sets_test_lib \
	sofs_SUITE \
	stdlib_SUITE \
	stdlib_bench_SUITE \
	string_SUITE \
	supervisor_1 \
	supervisor_2 \
	supervisor_3 \
	supervisor_4 \
	supervisor_deadlock \
	naughty_child \
	shell_SUITE \
	shell_docs_SUITE \
	shell_docs_markdown_SUITE \
	sigils_SUITE \
	supervisor_SUITE \
	supervisor_bridge_SUITE \
	sys_SUITE \
	sys_sp1 \
	sys_sp2 \
	tar_SUITE \
	timer_SUITE \
	timer_simple_SUITE \
	unicode_SUITE \
	unicode_util_SUITE \
	uri_string_SUITE \
	uri_string_property_test_SUITE \
	win32reg_SUITE \
	y2k_SUITE \
	select_SUITE \
	zip_SUITE \
	random_unicode_list \
	random_iolist \
	error_logger_forwarder \
	maps_SUITE \
	zstd_SUITE \
	zzz_SUITE

ERTS_MODULES= erts_test_utils
SASL_MODULES= otp_vsns
KERNEL_MODULES= rtnode

ERL_FILES=	$(MODULES:%=%.erl) \
		$(ERTS_MODULES:%=$(ERL_TOP)/erts/emulator/test/%.erl) \
		$(SASL_MODULES:%=$(ERL_TOP)/lib/sasl/test/%.erl) \
		$(KERNEL_MODULES:%=$(ERL_TOP)/lib/kernel/test/%.erl)

EXTRA_FILES= $(ERL_TOP)/otp_versions.table

# ----------------------------------------------------
# Release directory specification
# ----------------------------------------------------
RELSYSDIR = $(RELEASE_PATH)/stdlib_test

# ----------------------------------------------------
# FLAGS
# ----------------------------------------------------

ERL_COMPILE_FLAGS += -I$(ERL_TOP)/lib/kernel/include \
		+nowarn_missing_spec_documented \
		-I$(ERL_TOP)/lib/stdlib/include
ERL_COMPILE_FLAGS := $(filter-out +deterministic,$(ERL_COMPILE_FLAGS))

EBIN = .

EMAKEFILE=Emakefile
COVERFILE=stdlib.cover tty.cover

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

make_emakefile:
	$(ERL_TOP)/make/make_emakefile $(ERL_COMPILE_FLAGS) -o$(EBIN) \
		$(MODULES) $(ERTS_MODULES) $(SASL_MODULES) $(KERNEL_MODULES) \
	> $(EMAKEFILE)

tests $(TYPES): make_emakefile
	erl $(ERL_MAKE_FLAGS) -make

clean:
	rm -f $(EMAKEFILE)
	rm -f $(TARGET_FILES)
	rm -f core

docs:

# ----------------------------------------------------
# Release Target
# ----------------------------------------------------
include $(ERL_TOP)/make/otp_release_targets.mk

release_spec: opt

release_tests_spec: make_emakefile
	$(INSTALL_DIR) "$(RELSYSDIR)"
	$(INSTALL_DATA) stdlib.spec stdlib_bench.spec stdlib_gh.spec error_info.spec $(EMAKEFILE) \
		$(ERL_FILES) $(COVERFILE) $(EXTRA_FILES) "$(RELSYSDIR)"
	chmod -R u+w "$(RELSYSDIR)"
	@tar cf - *_SUITE_data property_test | (cd "$(RELSYSDIR)"; tar xf -)
	$(INSTALL_DIR) "$(RELSYSDIR)/stdlib_SUITE_data"
	$(INSTALL_DATA) $(ERL_TOP)/make/otp_version_tickets "$(RELSYSDIR)/stdlib_SUITE_data"

release_docs_spec:

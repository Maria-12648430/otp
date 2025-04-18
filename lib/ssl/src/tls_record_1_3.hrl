%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2018-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%
%%----------------------------------------------------------------------
%% Purpose: Record and constant definitions for the TLS-1.3-record protocol
%% see RFC 8446 not present in earlier versions
%%----------------------------------------------------------------------

-ifndef(tls_record_1_3).
-define(tls_record_1_3, true).

%% Common to TLS-1.3 and previous TLS versions 
%% Some definitions may not exist in TLS-1.3 this is 
%% handled elsewhere
-include("tls_record.hrl"). 
%% enum {
%%         invalid(0),
%%         %% defined in ssl_record.hrl
%%         change_cipher_spec(20),
%%         alert(21),
%%         handshake(22),
%%         application_data(23),
%%         heartbeat(24),  /* RFC 6520 */
%%         (255)
%%     } ContentType;

-define(INVALID, 0).
-define(LEGACY_VERSION, ?TLS_1_2).
-define(OPAQUE_TYPE, 23).

-record(tls_cipher_text, {  %% Equivalent of encrypted version of #ssl_tls from previous versions
                            %% decrypted version will still use #ssl_tls for code reuse purposes
                            %% with real values for content type and version
                            opaque_type = ?OPAQUE_TYPE,
                            legacy_version = ?LEGACY_VERSION :: ssl_record:ssl_version(),
                            encoded_record
                         }).

-endif. % -ifdef(tls_record_1_3).

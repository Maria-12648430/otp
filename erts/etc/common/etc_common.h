/*
 * %CopyrightBegin%
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright Ericsson AB 2017-2025. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * %CopyrightEnd%
 */
/*
 * Purpose: common includes for all etc programs
 */
#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#if !defined(__WIN32__)
#  include <dirent.h>
#  include <limits.h>
#  include <sys/stat.h>
#  include <sys/types.h>
#  include <unistd.h>
#else
#  include <windows.h>
#  include <io.h>
#  include <winbase.h>
#  include <process.h>
#  include <direct.h> // _getcwd
#endif

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/*
 * Make sure that MAXPATHLEN is defined.
 */
#ifndef MAXPATHLEN
#   ifdef PATH_MAX
#       define MAXPATHLEN PATH_MAX
#   else
#       define MAXPATHLEN 2048
#   endif
#endif

#include "erl_printf.h"

#ifdef __WIN32__
/* FIXME config_win32.h? */
#define HAVE_STRERROR 1
#define snprintf _snprintf
#endif

#ifdef __IOS__
#ifdef system
#undef system
#endif 
#define system(X) 0
#endif

#ifdef DEBUG
#  define ASSERT(Cnd) ((void)((Cnd) ? 1 : abort()))
#else
#  define ASSERT(Cnd)
#endif

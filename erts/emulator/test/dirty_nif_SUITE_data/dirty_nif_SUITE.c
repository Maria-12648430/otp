/*
 * %CopyrightBegin%
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright Ericsson AB 2009-2025. All Rights Reserved.
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
#include <erl_nif.h>
#include <assert.h>
#include <errno.h>
#ifdef __WIN32__
#include <windows.h>
#else
#include <unistd.h>
#endif
#include <stdio.h>
#include <string.h>

/*
 * Hack to get around this function missing from the NIF API.
 * TODO: Add this function/macro in the appropriate place, probably with
 *       enif_make_pid() in erl_nif_api_funcs.h
 */
#ifndef enif_make_port
#define enif_make_port(ENV, PORT) ((void)(ENV),(const ERL_NIF_TERM)((PORT)->port_id))
#endif

static ERL_NIF_TERM atom_badarg;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_false;
static ERL_NIF_TERM atom_lookup;
static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_pid;
static ERL_NIF_TERM atom_port;
static ERL_NIF_TERM atom_send;
static ERL_NIF_TERM atom_set_on_halt_handler;
static ERL_NIF_TERM atom_delay_halt;

typedef struct {
    int halting;
    int on_halt_wait;
    ErlNifMutex *mtx;
    ErlNifCond *cnd;
    char *filename;
} PrivData;

static PrivData *make_priv_data(void)
{
    PrivData *pdata = enif_alloc(sizeof(PrivData));
    if (!pdata)
        return NULL;
    pdata->halting = 0;
    pdata->on_halt_wait = 0;
    pdata->mtx = NULL;
    pdata->cnd = NULL;
    pdata->filename = NULL;
    return pdata;
}

static void unload(ErlNifEnv *env, void *priv_data)
{
    if (priv_data) {
        PrivData *pdata = priv_data;
        if (pdata->mtx)
            enif_mutex_destroy(pdata->mtx);
        if (pdata->cnd)
            enif_cond_destroy(pdata->cnd);
        if (pdata->filename)
            enif_free(pdata->filename);
        enif_free(pdata);
    }
}

static void on_halt(void *priv_data);

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info)
{
    int arity;
    const ERL_NIF_TERM *array;
    if (enif_get_tuple(env, load_info, &arity, &array)) {
        char atom_text[32];
        int err;
        unsigned filename_len;
        PrivData *pdata = NULL;

        if (arity < 1 || 3 < arity)
            return __LINE__;
        if (!enif_get_atom(env, array[0], &atom_text[0],
                           sizeof(atom_text), ERL_NIF_LATIN1)) {
            return __LINE__;
        }
        pdata = make_priv_data();
        if (!pdata)
            return __LINE__;
        if (strcmp(atom_text, "on_halt") == 0) {
            if (0 != enif_set_option(env, ERL_NIF_OPT_ON_HALT, on_halt)) {
                unload(env, pdata);
                return __LINE__;
            }
        }
        else if (strcmp(atom_text, "delay_halt") == 0) {
            if (0 != enif_set_option(env, ERL_NIF_OPT_DELAY_HALT)) {
                unload(env, pdata);
                return __LINE__;
            }
        }
        else if (strcmp(atom_text, "sync_halt") == 0) {
            if (0 != enif_set_option(env, ERL_NIF_OPT_ON_HALT, on_halt)) {
                unload(env, pdata);
                return __LINE__;
            }
            if (0 != enif_set_option(env, ERL_NIF_OPT_DELAY_HALT)) {
                unload(env, pdata);
                return __LINE__;
            }
            pdata->mtx = enif_mutex_create("sync_halt_dirty_nif_SUITE");
            pdata->cnd = enif_cond_create("sync_halt_dirty_nif_SUITE");
            if (!pdata->mtx || !pdata->cnd) {
                unload(env, pdata);
                return __LINE__;
            }
        }
        else {
            unload(env, pdata);
            return __LINE__;
        }

        if (arity >= 2) {
            if (!enif_get_list_length(env, array[1], &filename_len)) {
                unload(env, pdata);
                return __LINE__;
            }
            if (filename_len > 0) {
                filename_len++;
                pdata->filename = enif_alloc(filename_len);
                if (!pdata->filename) {
                    unload(env, pdata);
                    return __LINE__;
                }
                if (filename_len != enif_get_string(env,
                                                    array[1],
                                                    pdata->filename,
                                                    filename_len,
                                                    ERL_NIF_LATIN1)) {
                    unload(env, pdata);
                    return __LINE__;
                }
            }
        }
        if (arity == 3) {
            if (!enif_get_int(env, array[2], &pdata->on_halt_wait)
                || pdata->on_halt_wait < 0
                || pdata->on_halt_wait*1000 < 0) {
                unload(env, pdata);
                return __LINE__;
            }
        }
        *priv_data = (void *) pdata;
    }

    atom_badarg = enif_make_atom(env, "badarg");
    atom_error = enif_make_atom(env, "error");
    atom_false = enif_make_atom(env,"false");
    atom_lookup = enif_make_atom(env, "lookup");
    atom_ok = enif_make_atom(env,"ok");
    atom_pid = enif_make_atom(env, "pid");
    atom_port = enif_make_atom(env, "port");
    atom_send = enif_make_atom(env, "send");
    atom_set_on_halt_handler = enif_make_atom(env, "set_on_halt_handler");
    atom_delay_halt = enif_make_atom(env, "delay_halt");

    return 0;
}

static int upgrade(ErlNifEnv* env, void** priv_data, void** old_priv_data, ERL_NIF_TERM load_info)
{
    return load(env, priv_data, load_info);
}

static ERL_NIF_TERM lib_loaded(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    return enif_make_atom(env, "true");
}

static int have_dirty_schedulers(void)
{
    ErlNifSysInfo si;
    enif_system_info(&si, sizeof(si));
    return si.dirty_scheduler_support;
}

static ERL_NIF_TERM dirty_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    int n;
    char s[10];
    ErlNifBinary b;
    if (have_dirty_schedulers()) {
	assert(ERL_NIF_THR_DIRTY_CPU_SCHEDULER == enif_thread_type()
	       || ERL_NIF_THR_DIRTY_IO_SCHEDULER == enif_thread_type());
    }
    assert(argc == 3);
    enif_get_int(env, argv[0], &n);
    enif_get_string(env, argv[1], s, sizeof s, ERL_NIF_LATIN1);
    enif_inspect_binary(env, argv[2], &b);
    return enif_make_tuple3(env,
			    enif_make_int(env, n),
			    enif_make_string(env, s, ERL_NIF_LATIN1),
			    enif_make_binary(env, &b));
}

static ERL_NIF_TERM call_dirty_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    int n;
    char s[10];
    ErlNifBinary b;
    assert(ERL_NIF_THR_NORMAL_SCHEDULER == enif_thread_type());
    assert(argc == 3);
    if (have_dirty_schedulers()) {
	if (enif_get_int(env, argv[0], &n) &&
	    enif_get_string(env, argv[1], s, sizeof s, ERL_NIF_LATIN1) &&
	    enif_inspect_binary(env, argv[2], &b))
	    return enif_schedule_nif(env, "call_dirty_nif", ERL_NIF_DIRTY_JOB_CPU_BOUND, dirty_nif, argc, argv);
	else
	    return enif_make_badarg(env);
    } else {
	return dirty_nif(env, argc, argv);
    }
}

static ERL_NIF_TERM send_from_dirty_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ERL_NIF_TERM result;
    ErlNifPid pid;
    int res;

    if (!enif_get_local_pid(env, argv[0], &pid))
	return enif_make_badarg(env);
    result = enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_pid(env, &pid));
    res = enif_send(env, &pid, NULL, result);
    if (!res)
	return enif_make_badarg(env);
    else
	return result;
}

static ERL_NIF_TERM send_wait_from_dirty_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ERL_NIF_TERM result;
    ErlNifPid pid;
    int res;

    if (!enif_get_local_pid(env, argv[0], &pid))
	return enif_make_badarg(env);
    result = enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_pid(env, &pid));
    res = enif_send(env, &pid, NULL, result);

#ifdef __WIN32__
    Sleep(2000);
#else
    sleep(2);
#endif

    if (!res)
	return enif_make_badarg(env);
    else
	return result;
}

static ERL_NIF_TERM call_dirty_nif_exception(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    switch (argc) {
    case 1: {
	int arg;
	if (enif_get_int(env, argv[0], &arg) && arg < 2) {
	    ERL_NIF_TERM args[255];
	    int i;
	    args[0] = argv[0];
	    for (i = 1; i < 255; i++)
		args[i] = enif_make_int(env, i);
	    return enif_schedule_nif(env, "call_dirty_nif_exception", ERL_NIF_DIRTY_JOB_CPU_BOUND,
				     call_dirty_nif_exception, 255, args);
	} else {
	    return enif_raise_exception(env, argv[0]);
	}
    }
    case 2: {
        int return_badarg_directly;
        enif_get_int(env, argv[0], &return_badarg_directly);
        assert(return_badarg_directly == 1 || return_badarg_directly == 0);
        if (return_badarg_directly)
            return enif_make_badarg(env);
        else {
            /* ignore return value */ enif_make_badarg(env);
            return enif_make_atom(env, "ok");
        }
    }
    default:
	return enif_schedule_nif(env, "call_dirty_nif_exception", ERL_NIF_DIRTY_JOB_CPU_BOUND,
				 call_dirty_nif_exception, argc-1, argv);
    }
}

static ERL_NIF_TERM call_dirty_nif_zero_args(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    int i;
    ERL_NIF_TERM result[1000];
    ERL_NIF_TERM ok = enif_make_atom(env, "ok");
    assert(argc == 0);
    for (i = 0; i < sizeof(result)/sizeof(*result); i++) {
	result[i] = ok;
    }
    return enif_make_list_from_array(env, result, i);
}

static ERL_NIF_TERM
dirty_sleeper(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifPid pid;
    ErlNifEnv* msg_env = NULL;

    assert(ERL_NIF_THR_DIRTY_CPU_SCHEDULER == enif_thread_type()
	   || ERL_NIF_THR_DIRTY_IO_SCHEDULER == enif_thread_type());

    /* If we get a pid argument, it indicates a process involved in the
       test wants a message from us. Prior to the sleep we send a 'ready'
       message, and then after the sleep, send a 'done' message. */
    if (argc == 1 && enif_get_local_pid(env, argv[0], &pid))
        enif_send(env, &pid, NULL, enif_make_atom(env, "ready"));

#ifdef __WIN32__
    Sleep(2000);
#else
    sleep(2);
#endif

    if (argc == 1)
        enif_send(env, &pid, NULL, enif_make_atom(env, "done"));

    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM dirty_call_while_terminated_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifPid self;
    ERL_NIF_TERM result, self_term;
    ErlNifPid to;
    ErlNifEnv* menv;
    int res;

    if (!enif_get_local_pid(env, argv[0], &to))
	return enif_make_badarg(env);

    if (!enif_self(env, &self))
	return enif_make_badarg(env);

    self_term = enif_make_pid(env, &self);

    menv = enif_alloc_env();
    result = enif_make_tuple2(menv, enif_make_atom(menv, "dirty_alive"), self_term);
    res = enif_send(env, &to, menv, result);
    enif_free_env(menv);
    if (!res)
	return enif_make_badarg(env);

    /* Wait until we have been killed */
    while (enif_is_process_alive(env, &self))
	;

    result = enif_make_tuple2(env, enif_make_atom(env, "dirty_dead"), self_term);
    res = enif_send(env, &to, NULL, result);

#ifdef __WIN32__
    Sleep(1000);
#else
    sleep(1);
#endif

    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM dirty_heap_access_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ERL_NIF_TERM res = enif_make_list(env, 0);
    int i;
    assert(ERL_NIF_THR_DIRTY_CPU_SCHEDULER == enif_thread_type()
	   || ERL_NIF_THR_DIRTY_IO_SCHEDULER == enif_thread_type());
    for (i = 0; i < 1000; i++)
	res = enif_make_list_cell(env, enif_make_copy(env, argv[0]), res);

    return res;
}

/*
 * enif_whereis_... tests
 * subset of the functions in nif_SUITE.c
 */

enum {
    /* results */
    WHEREIS_SUCCESS,
    WHEREIS_ERROR_TYPE,
    WHEREIS_ERROR_LOOKUP,
    WHEREIS_ERROR_SEND,
    /* types */
    WHEREIS_LOOKUP_PID,     /* enif_whereis_pid() */
    WHEREIS_LOOKUP_PORT     /* enif_whereis_port() */
};

typedef union {
    ErlNifPid   pid;
    ErlNifPort  port;
} whereis_term_data_t;

static int whereis_type(ERL_NIF_TERM type)
{
    if (enif_is_identical(type, atom_pid))
        return WHEREIS_LOOKUP_PID;

    if (enif_is_identical(type, atom_port))
        return WHEREIS_LOOKUP_PORT;

    return WHEREIS_ERROR_TYPE;
}

static int whereis_lookup_internal(
    ErlNifEnv* env, int type, ERL_NIF_TERM name, whereis_term_data_t* out)
{
    if (type == WHEREIS_LOOKUP_PID)
        return enif_whereis_pid(env, name, & out->pid)
            ? WHEREIS_SUCCESS : WHEREIS_ERROR_LOOKUP;

    if (type == WHEREIS_LOOKUP_PORT)
        return enif_whereis_port(env, name, & out->port)
            ? WHEREIS_SUCCESS : WHEREIS_ERROR_LOOKUP;

    return WHEREIS_ERROR_TYPE;
}

static int whereis_send_internal(
    ErlNifEnv* env, int type, whereis_term_data_t* to, ERL_NIF_TERM msg)
{
    if (type == WHEREIS_LOOKUP_PID)
        return enif_send(env, & to->pid, NULL, msg)
            ? WHEREIS_SUCCESS : WHEREIS_ERROR_SEND;

    if (type == WHEREIS_LOOKUP_PORT)
        return enif_port_command(env, & to->port, NULL, msg)
            ? WHEREIS_SUCCESS : WHEREIS_ERROR_SEND;

    return WHEREIS_ERROR_TYPE;
}

static int whereis_lookup_term(
    ErlNifEnv* env, int type, ERL_NIF_TERM name, ERL_NIF_TERM* out)
{
    whereis_term_data_t res;
    int rc = whereis_lookup_internal(env, type, name, &res);
    if (rc == WHEREIS_SUCCESS) {
        switch (type) {
            case WHEREIS_LOOKUP_PID:
                *out = enif_make_pid(env, & res.pid);
                break;
            case WHEREIS_LOOKUP_PORT:
                *out = enif_make_port(env, & res.port);
                break;
            default:
                rc = WHEREIS_ERROR_TYPE;
                break;
        }
    }
    return rc;
}

static ERL_NIF_TERM whereis_result_term(ErlNifEnv* env, int result)
{
    ERL_NIF_TERM err;
    switch (result)
    {
        case WHEREIS_SUCCESS:
            return atom_ok;
        case WHEREIS_ERROR_LOOKUP:
            err = atom_lookup;
            break;
        case WHEREIS_ERROR_SEND:
            err = atom_send;
            break;
        case WHEREIS_ERROR_TYPE:
            err = atom_badarg;
            break;
        default:
            err = enif_make_int(env, -result);
            break;
    }
    return enif_make_tuple2(env, atom_error, err);
}

/* whereis_term(Type, Name) -> pid() | port() | false */
static ERL_NIF_TERM
whereis_term(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ERL_NIF_TERM ret;
    int type, rc;

    assert(argc == 2);

    if ((type = whereis_type(argv[0])) == WHEREIS_ERROR_TYPE)
        return enif_make_badarg(env);

    rc = whereis_lookup_term(env, type, argv[1], &ret);
    return (rc == WHEREIS_SUCCESS) ? ret : atom_false;
}

/* whereis_send(Type, Name, Message) -> ok | {error, Reason} */
static ERL_NIF_TERM
whereis_send(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    whereis_term_data_t to;
    int type, rc;

    assert(argc == 3);
    if (!enif_is_atom(env, argv[1]))
        return enif_make_badarg(env);

    if ((type = whereis_type(argv[0])) == WHEREIS_ERROR_TYPE)
        return enif_make_badarg(env);

    rc = whereis_lookup_internal(env, type, argv[1], & to);
    if (rc == WHEREIS_SUCCESS)
        rc = whereis_send_internal(env, type, & to, argv[2]);

    return whereis_result_term(env, rc);
}

static ERL_NIF_TERM dirty_terminating_literal_access(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifPid to, self;
    ERL_NIF_TERM copy, self_term, result;
    ErlNifEnv* copy_env, *menv;

    /*
     * Pid of test proc in argv[0]
     * A literal term in argv[1]
     */
    
    assert(argc == 2);
    
    if (!enif_get_local_pid(env, argv[0], &to))
	return enif_make_badarg(env);

    if (!enif_self(env, &self))
	return enif_make_badarg(env);

    self_term = enif_make_pid(env, &self);

    copy_env = enif_alloc_env();
    copy = enif_make_copy(copy_env, argv[1]);
    if (!enif_is_identical(copy, argv[1]))
        return enif_make_badarg(env);
    
    menv = enif_alloc_env();
    result = enif_make_tuple2(menv, enif_make_atom(menv, "dirty_alive"), self_term);
    enif_send(env, &to, menv, result);
    enif_free_env(menv);

    while (enif_is_current_process_alive(env));

    /* Give the system time to try and remove the literal area */
    
#ifdef __WIN32__
    Sleep(3000);
#else
    sleep(3);
#endif

    /*
     * If the system was successful in removing the area,
     * the debug compiled emulator will have overwritten
     * the data referred by argv[1]
     */
    
    if (!enif_is_identical(copy, argv[1]))
        abort();

    enif_free_env(copy_env);

    return self_term;
}

static int fn_write_ok(char *filename)
{
    FILE *file = fopen(filename, "w");
    if (!file)
        return EINVAL;
    if (1 != fwrite("ok", 2, 1, file))
        return EINVAL;
    fclose(file);
    return 0;
}

static int efn_write_ok(ErlNifEnv *env, const ERL_NIF_TERM arg)
{
    int res;
    unsigned filename_len;
    char *filename;

    if (!enif_get_list_length(env, arg, &filename_len) || filename_len < 2) {
        res = EINVAL;
        goto done;
    }
    filename_len++;
    filename = enif_alloc(filename_len);
    if (!filename) {
        res = ENOMEM;
        goto done;
    }
    if (filename_len != enif_get_string(env,
                                        arg,
                                        filename,
                                        filename_len,
                                        ERL_NIF_LATIN1)) {
        res = EINVAL;
        goto done;
    }
    res = fn_write_ok(filename);
done:
    if (filename)
        enif_free(filename);
    switch (res) {
    case 0:
        return atom_ok;
    case ENOMEM:
        return enif_raise_exception(env, enif_make_atom(env, "enomem"));
    default:
        return enif_make_badarg(env);
    }
}

static ERL_NIF_TERM delay_halt(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    ERL_NIF_TERM msg;
    ErlNifPid receiver, self;
    int res, secs;

    assert(argc == 3);

    if (!enif_get_int(env, argv[2], &secs))
        return enif_make_badarg(env);
    if (secs < 0 || secs*1000 < 0)
        return enif_make_badarg(env);
    if (!enif_self(env, &self))
	return enif_make_badarg(env);
    if (!enif_get_local_pid(env, argv[0], &receiver))
	return enif_make_badarg(env);
    msg = enif_make_tuple2(env, enif_make_atom(env, "delay_halt"), enif_make_pid(env, &self));
    res = enif_send(env, &receiver, NULL, msg);
    if (!res)
	return enif_make_badarg(env);

#ifdef __WIN32__
    Sleep(secs*1000);
#else
    sleep(secs);
#endif
    return efn_write_ok(env, argv[1]);
}

static ERL_NIF_TERM sync_halt(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    ERL_NIF_TERM msg;
    ErlNifPid receiver, self;
    int res;
    PrivData *pdata = enif_priv_data(env);
    if (!pdata)
        return enif_raise_exception(env, enif_make_atom(env, "missing_priv_data"));
    assert(argc == 2);
    if (!enif_self(env, &self))
	return enif_make_badarg(env);
    if (!enif_get_local_pid(env, argv[0], &receiver))
	return enif_make_badarg(env);
    msg = enif_make_tuple2(env, enif_make_atom(env, "sync_halt"), enif_make_pid(env, &self));
    res = enif_send(env, &receiver, NULL, msg);
    if (!res)
	return enif_make_badarg(env);
    enif_mutex_lock(pdata->mtx);
    while (!pdata->halting)
        enif_cond_wait(pdata->cnd, pdata->mtx);
    enif_mutex_unlock(pdata->mtx);
    return efn_write_ok(env, argv[1]);
}

static ERL_NIF_TERM set_halt_option_from_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    if (argv[0] == atom_set_on_halt_handler) {
        if (0 == enif_set_option(env, ERL_NIF_OPT_ON_HALT, on_halt))
            return atom_ok;
        return atom_error;
    }
    else if (argv[0] == atom_delay_halt) {
        if (0 == enif_set_option(env, ERL_NIF_OPT_DELAY_HALT))
            return atom_ok;
        return atom_error;
    }
    return enif_make_badarg(env);
}

static void on_halt(void *priv_data)
{
    PrivData *pdata = (PrivData *)priv_data;
    int res;
#ifdef __WIN32__
    Sleep(pdata->on_halt_wait*1000);
#else
    sleep(pdata->on_halt_wait);
#endif
    if (pdata->mtx) {
        enif_mutex_lock(pdata->mtx);
        assert(!pdata->halting);
        pdata->halting = !0;
        enif_cond_broadcast(pdata->cnd);
        enif_mutex_unlock(pdata->mtx);
    }
    res = fn_write_ok(pdata->filename);
    assert(res == 0);
}

static ErlNifFunc nif_funcs[] =
{
    {"lib_loaded", 0, lib_loaded},
    {"call_dirty_nif", 3, call_dirty_nif},
    {"send_from_dirty_nif", 1, send_from_dirty_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"send_wait_from_dirty_nif", 1, send_wait_from_dirty_nif, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"call_dirty_nif_exception", 1, call_dirty_nif_exception, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"call_dirty_nif_zero_args", 0, call_dirty_nif_zero_args, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"dirty_sleeper", 0, dirty_sleeper, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_sleeper", 1, dirty_sleeper, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"dirty_call_while_terminated_nif", 1, dirty_call_while_terminated_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"dirty_heap_access_nif", 1, dirty_heap_access_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"whereis_send", 3, whereis_send, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"whereis_term", 2, whereis_term, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"dirty_terminating_literal_access", 2, dirty_terminating_literal_access, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"delay_halt_normal", 3, delay_halt, 0},
    {"delay_halt_io_bound", 3, delay_halt, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"delay_halt_cpu_bound", 3, delay_halt, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"sync_halt_io_bound", 2, sync_halt, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"sync_halt_cpu_bound", 2, sync_halt, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"set_halt_option_from_nif_normal", 1, set_halt_option_from_nif, 0},
    {"set_halt_option_from_nif_io_bound", 1, set_halt_option_from_nif, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"set_halt_option_from_nif_cpu_bound", 1, set_halt_option_from_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

ERL_NIF_INIT(dirty_nif_SUITE,nif_funcs,load,NULL,upgrade,unload)

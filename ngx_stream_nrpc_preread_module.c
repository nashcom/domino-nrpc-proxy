/*
###########################################################################
# NRPC Stream pre-read NGINX Module                                       #
# Version 0.9.2 29.03.2026                                                #
# (C) Copyright Daniel Nashed/NashCom 2023-2026                           #
#                                                                         #
# Licensed under the Apache License, Version 2.0 (the "License");         #
# you may not use this file except in compliance with the License.        #
# You may obtain a copy of the License at                                 #
#                                                                         #
#      http://www.apache.org/licenses/LICENSE-2.0                         #
#                                                                         #
# Unless required by applicable law or agreed to in writing, software     #
# distributed under the License is distributed on an "AS IS" BASIS,       #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.#
# See the License for the specific language governing permissions and     #
# limitations under the License.                                          #
###########################################################################
*/

#include "nrpc_version.h"

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>


u_char g_CN [] = "CN=";

typedef struct
{
    ngx_flag_t fEnabled;
    ngx_flag_t fReplaceDots;

} ngx_stream_nrpc_preread_srv_conf_t;

typedef struct
{
    ngx_str_t  DominoServerName;
    ngx_str_t  ServerName;
    ngx_str_t  OrgName;
    ngx_flag_t fReplaceDots;

} ngx_stream_nrpc_preread_ctx_t;

static ngx_int_t ngx_stream_nrpc_preread_handler (ngx_stream_session_t *s);
static ngx_int_t ngx_stream_nrpc_preread_server_name_variable (ngx_stream_session_t *s, ngx_stream_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_stream_nrpc_preread_org_name_variable (ngx_stream_session_t *s, ngx_stream_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_stream_nrpc_preread_domino_server_variable (ngx_stream_session_t *s, ngx_stream_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_stream_nrpc_preread_add_variables (ngx_conf_t *cf);
static ngx_int_t ngx_stream_nrpc_preread_init (ngx_conf_t *cf);
static ngx_int_t ngx_stream_nrpc_preread_init_module (ngx_cycle_t *cycle);

static void *ngx_stream_nrpc_preread_create_srv_conf (ngx_conf_t *cf);
static char *ngx_stream_nrpc_preread_merge_srv_conf (ngx_conf_t *cf, void *parent, void *child);

static int ngx_GetWordLE (u_char *pBuffer, size_t offset);
static const u_char *ngx_FindInBuffer (const u_char *pBuffer, const u_char *pLast, const u_char *pszFindStr);


static ngx_command_t ngx_stream_nrpc_preread_commands[] =
{
    { ngx_string("nrpc_preread"),
        NGX_STREAM_MAIN_CONF | NGX_STREAM_SRV_CONF | NGX_CONF_FLAG,
        ngx_conf_set_flag_slot,
        NGX_STREAM_SRV_CONF_OFFSET,
        offsetof (ngx_stream_nrpc_preread_srv_conf_t, fEnabled),
        NULL 
    },

    { ngx_string("nrpc_preread_replacedots"),
        NGX_STREAM_MAIN_CONF | NGX_STREAM_SRV_CONF | NGX_CONF_FLAG,
        ngx_conf_set_flag_slot,
        NGX_STREAM_SRV_CONF_OFFSET,
        offsetof (ngx_stream_nrpc_preread_srv_conf_t, fReplaceDots),
        NULL
    },

    ngx_null_command
};

static ngx_stream_module_t ngx_stream_nrpc_preread_module_ctx =
{
    ngx_stream_nrpc_preread_add_variables,
    ngx_stream_nrpc_preread_init,
    NULL,
    NULL,
    ngx_stream_nrpc_preread_create_srv_conf,
    ngx_stream_nrpc_preread_merge_srv_conf
};

ngx_module_t ngx_stream_nrpc_preread_module =
{
    NGX_MODULE_V1,
    &ngx_stream_nrpc_preread_module_ctx, /* module context */
    ngx_stream_nrpc_preread_commands,    /* module directives */
    NGX_STREAM_MODULE,                   /* module type */
    NULL,                                /* init master */
    ngx_stream_nrpc_preread_init_module, /* init module */
    NULL,                                /* init process */
    NULL,                                /* init thread */
    NULL,                                /* exit thread */
    NULL,                                /* exit process */
    NULL,                                /* exit master */
    NGX_MODULE_V1_PADDING
};

static ngx_stream_variable_t ngx_stream_nrpc_preread_vars[] =
{
    { ngx_string("nrpc_preread_server_name"),   NULL, ngx_stream_nrpc_preread_server_name_variable, 0, 0, 0 },
    { ngx_string("nrpc_preread_org_name"),      NULL, ngx_stream_nrpc_preread_org_name_variable, 0, 0, 0 },
    { ngx_string("nrpc_preread_domino_server"), NULL, ngx_stream_nrpc_preread_domino_server_variable, 0, 0, 0 },
    ngx_stream_null_variable
};


static int ngx_GetWordLE (u_char *pBuffer, size_t offset)
{
    return *(pBuffer + offset) + *(pBuffer + offset + 1) * 256;
}

static const u_char *ngx_FindInBuffer (const u_char *pBuffer, const u_char *pLast, const u_char *pszFindStr)
{
    const u_char *pFind = NULL;
    const u_char *pPos  = NULL;
    const u_char *p     = NULL;

    if ( (NULL == pBuffer) || (NULL == pLast) || (NULL == pszFindStr) )
        return NULL;

    while (pBuffer < pLast)
    {
        pFind = (const u_char *) ngx_strlchr ((u_char *)pBuffer, (u_char *)pLast, (u_char)*pszFindStr);

        if (NULL == pFind)
            return NULL;

        /* Now compare the full string */
        pPos = pFind + 1;
        p = (u_char *) pszFindStr + 1;
        
        while (pPos < pLast)
        {
            /* No chars to match left -> found */
            if (!*p)
                return pFind;

	    if (*p != *pPos)
                break;

            pPos++;
            p++;

        } /* while */

        /* Search again after found first char */
        pBuffer = pPos + 1;

    } /* while */

    return NULL;
}


static ngx_int_t ngx_stream_nrpc_preread_handler (ngx_stream_session_t *s)
{
    ngx_str_t DominoServerName = {0};

    u_char *p       = NULL;
    u_char *pLast   = NULL;
    u_char *pBuffer = NULL;

    ngx_connection_t *c = NULL;

    ngx_stream_nrpc_preread_ctx_t      *pCtx         = NULL;
    ngx_stream_nrpc_preread_srv_conf_t *pPreReadConf = NULL;

    if (NULL == s)
        return NGX_DECLINED;

    pPreReadConf = ngx_stream_get_module_srv_conf (s, ngx_stream_nrpc_preread_module);

    if (NULL == pPreReadConf)
        return NGX_DECLINED;

    if (!pPreReadConf->fEnabled)
        return NGX_DECLINED;

    c = s->connection;

    if (NULL == c)
        return NGX_AGAIN;

    if (c->type != SOCK_STREAM)
        return NGX_DECLINED;

    if (NULL == c->buffer)
        return NGX_AGAIN;

    pBuffer = c->buffer->pos;
    pLast   = c->buffer->last;

    if ( (NULL == pBuffer) || (NULL == pLast))
        return NGX_AGAIN;

    DominoServerName.data = (u_char *) ngx_FindInBuffer (pBuffer, pLast, g_CN);

    if (DominoServerName.data)
        DominoServerName.len = ngx_GetWordLE ((u_char *) (DominoServerName.data - 2), 0);

    if ((NULL == DominoServerName.data) || (0 == DominoServerName.len))
    {
       ngx_log_error (NGX_LOG_ERR, c->log, 0, "No server found");
       return NGX_AGAIN;
    }

    if (DominoServerName.len > 255)
    {
       ngx_log_error (NGX_LOG_ERR, c->log, 0, "Server name too long (%i)", DominoServerName.len);
       return NGX_AGAIN;
    }

    /* Only if found, allocate context & add variable */

    pCtx = ngx_stream_get_module_ctx (s, ngx_stream_nrpc_preread_module);

    if (NULL == pCtx)
    {
        pCtx = ngx_pcalloc (c->pool, sizeof (ngx_stream_nrpc_preread_ctx_t));

        if (NULL == pCtx)
        {
            ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot allocate context");
            return NGX_ERROR;
        }

        ngx_stream_set_ctx (s, pCtx, ngx_stream_nrpc_preread_module);
    }

    pCtx->DominoServerName.data = ngx_pnalloc (c->pool, DominoServerName.len + 1); /* Leave room for null terminator */

    if (NULL == pCtx->DominoServerName.data)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot allocate memory for server name");
        return NGX_ERROR;
    }

    p = (u_char *) ngx_movemem (pCtx->DominoServerName.data, DominoServerName.data, DominoServerName.len);

    if (NULL == p)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot copy server name");
        return NGX_ERROR;
    }

    /* Null terminate server name */
    *p = '\0';

    pCtx->DominoServerName.len = DominoServerName.len;

    /* Pass configuration via context */
    pCtx->fReplaceDots = pPreReadConf->fReplaceDots;

    ngx_log_error (NGX_LOG_DEBUG, c->log, 0, "Server found: [%s]", pCtx->DominoServerName.data);
    return NGX_OK;
}


static ngx_int_t ngx_stream_nrpc_preread_domino_server_variable (ngx_stream_session_t *s, ngx_variable_value_t *v, uintptr_t data)
{
    ngx_stream_nrpc_preread_ctx_t *pCtx = NULL;

    pCtx = ngx_stream_get_module_ctx (s, ngx_stream_nrpc_preread_module);

    if (NULL == pCtx)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    if (0 == pCtx->DominoServerName.len)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    v->valid        = 1;
    v->no_cacheable = 0;
    v->not_found    = 0;

    v->data = pCtx->DominoServerName.data;
    v->len  = pCtx->DominoServerName.len;

    return NGX_OK;
}


static ngx_int_t ngx_stream_nrpc_preread_server_name_variable (ngx_stream_session_t *s, ngx_variable_value_t *v, uintptr_t data)
{
    ngx_stream_nrpc_preread_ctx_t *pCtx = NULL;
    ngx_connection_t *c = NULL; 

    size_t ServerLen = 0;

    const char *pBegin = NULL;
    const char *pEnd   = NULL;
    const char *pFind  = NULL;
    const char *pSlash = NULL;
    char *p = NULL;

    c = s->connection;

    if (NULL == c)
        return NGX_AGAIN;

    pCtx = ngx_stream_get_module_ctx (s, ngx_stream_nrpc_preread_module);

    if (NULL == pCtx)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    if (0 == pCtx->DominoServerName.len)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    pBegin = (char *) pCtx->DominoServerName.data;
    pEnd   = (char *) pBegin + pCtx->DominoServerName.len;

    pFind = ngx_strstr (pBegin, "=");

    /* Skip before "=" (actually "CN=" but this avoids case in-sensitive checks)  */

    if (pFind)
        pBegin = pFind + 1;
  
    /* Truncate server name before "/" */

    pSlash = ngx_strstr (pBegin, "/");

    if (pSlash)
        pEnd = pSlash;

    ServerLen = pEnd - pBegin;

    if (0 == ServerLen)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    /* Allocate server name and pass the variable */

    pCtx->ServerName.data = ngx_pnalloc (c->pool, ServerLen + 1); /* Leave room for null terminator */

    if (NULL == pCtx->ServerName.data)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot allocate memory for server name");
        return NGX_ERROR;
    }

    p = (char *) ngx_movemem (pCtx->ServerName.data, pBegin, ServerLen);

    if (NULL == p)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot copy server name");
        return NGX_ERROR;
    }

    /* Null terminate server name */
    *p = '\0';

    p = (char *) pCtx->ServerName.data;

    /* Convert ' ' into '-' and '.' to '-' if configured */
    while (*p)
    {
        switch (*p)
        {
          case ' ':
            *p = '-';
            break;

          case '.':
            if (pCtx->fReplaceDots)
              *p = '-';
            break;

          default:
            *p = ngx_tolower (*p);
        } /* switch */

        p++;

    } /* while */

    pCtx->ServerName.len = ServerLen;

    v->valid        = 1;
    v->no_cacheable = 0;
    v->not_found    = 0;

    v->data = pCtx->ServerName.data;
    v->len  = pCtx->ServerName.len;

    ngx_log_error (NGX_LOG_NOTICE, c->log, 0, "Server [%s] -> CN: [%s]", pCtx->DominoServerName.data, pCtx->ServerName.data);

    return NGX_OK;
}

static ngx_int_t ngx_stream_nrpc_preread_org_name_variable (ngx_stream_session_t *s, ngx_variable_value_t *v, uintptr_t data)
{
    ngx_stream_nrpc_preread_ctx_t *pCtx = NULL;
    ngx_connection_t *c = NULL; 

    size_t OrgLen = 0;

    const char *pBegin = NULL;
    const char *pEnd   = NULL;
    const char *pFind  = NULL;
    const char *pSlash = NULL;

    char *p = NULL;

    c = s->connection;

    if (NULL == c)
        return NGX_AGAIN;

    pCtx = ngx_stream_get_module_ctx (s, ngx_stream_nrpc_preread_module);

    if (NULL == pCtx)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    if (0 == pCtx->DominoServerName.len)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    pBegin = (char *) pCtx->DominoServerName.data;
    pEnd   = (char *) pBegin + pCtx->DominoServerName.len;

    pFind  = ngx_strstr (pBegin, "/O=");
    if (NULL == pFind)
        pFind  = ngx_strstr (pBegin, "/o=");

    if (NULL == pFind)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Organization not found!");
        v->not_found = 1;
        return NGX_OK;
    }

    /* Skip org prefix */
    pBegin = pFind + 3;
  
    /* Truncate org name before "/" */

    pSlash = ngx_strstr (pBegin, "/");

    if (pSlash)
    {
        pEnd = pSlash;
    }

    OrgLen = pEnd - pBegin;

    if (0 == OrgLen)
    {
        v->not_found = 1;
        return NGX_OK;
    }

    /* Allocate org name and pass the variable */

    pCtx->OrgName.data = ngx_pnalloc (c->pool, OrgLen + 1); /* Leave room for null terminator */

    if (NULL == pCtx->OrgName.data)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot allocate memory for org name");
        return NGX_ERROR;
    }

    p = (char *) ngx_movemem (pCtx->OrgName.data, pBegin, OrgLen);

    if (NULL == p)
    {
        ngx_log_error (NGX_LOG_ERR, c->log, 0, "Cannot copy org name");
        return NGX_ERROR;
    }

    /* Null terminate org name */
    *p = '\0';

    p = (char *) pCtx->OrgName.data;

    /* Convert ' ' into '-' and '.' to '-' if configured */
    while (*p)
    {
        switch (*p)
        {
          case ' ':
            *p = '-';
            break;

          case '.':
            if (pCtx->fReplaceDots)
              *p = '-';
            break;

          default:
            *p = ngx_tolower (*p);
        } /* switch */

        p++;

    } /* while */

    pCtx->OrgName.len = OrgLen;

    v->valid        = 1;
    v->no_cacheable = 0;
    v->not_found    = 0;

    v->data = pCtx->OrgName.data;
    v->len  = pCtx->OrgName.len;

    ngx_log_error (NGX_LOG_NOTICE, c->log, 0, "Server [%s] -> Org: [%s]", pCtx->DominoServerName.data, pCtx->OrgName.data);

    return NGX_OK;
}

static ngx_int_t ngx_stream_nrpc_preread_add_variables (ngx_conf_t *cf)
{
    ngx_stream_variable_t  *pVar = NULL;
    ngx_stream_variable_t  *v    = NULL;

    for (v = ngx_stream_nrpc_preread_vars; v->name.len; v++) 
    {
        pVar = ngx_stream_add_variable (cf, &v->name, v->flags);

        if (NULL == pVar)
            return NGX_ERROR;

        pVar->get_handler = v->get_handler;
        pVar->data = v->data;
    }

    return NGX_OK;
}

static void *ngx_stream_nrpc_preread_create_srv_conf (ngx_conf_t *cf)
{
    ngx_stream_nrpc_preread_srv_conf_t *pConf = NULL;

    if (NULL == cf)
        return NULL;

    pConf = ngx_pcalloc (cf->pool, sizeof (ngx_stream_nrpc_preread_srv_conf_t));

    if (NULL == pConf)
        return NULL;

    pConf->fEnabled     = NGX_CONF_UNSET;
    pConf->fReplaceDots = NGX_CONF_UNSET;

    return pConf;
}

static char *ngx_stream_nrpc_preread_merge_srv_conf (ngx_conf_t *cf, void *parent, void *child)
{
    ngx_stream_nrpc_preread_srv_conf_t *pPrev = parent;
    ngx_stream_nrpc_preread_srv_conf_t *pConf = child;

    ngx_conf_merge_value (pConf->fEnabled,     pPrev->fEnabled, 0);
    ngx_conf_merge_value (pConf->fReplaceDots, pPrev->fReplaceDots, 0);
    return NGX_CONF_OK;
}

static ngx_int_t ngx_stream_nrpc_preread_init (ngx_conf_t *cf)
{
    ngx_stream_handler_pt        *pHandlerPT = NULL;
    ngx_stream_core_main_conf_t  *pMainConf  = NULL;

    if (NULL == cf)
        return NGX_ERROR;

    pMainConf = ngx_stream_conf_get_module_main_conf (cf, ngx_stream_core_module);

    pHandlerPT = ngx_array_push (&pMainConf->phases[NGX_STREAM_PREREAD_PHASE].handlers);

    if (NULL == pHandlerPT)
    {
        ngx_log_error (NGX_LOG_ERR, cf->log, 0, "Cannot push config handler");
        return NGX_ERROR;
    }

    *pHandlerPT = ngx_stream_nrpc_preread_handler;

    return NGX_OK;
}

static ngx_int_t ngx_stream_nrpc_preread_init_module (ngx_cycle_t *cycle)
{
    if (NULL == cycle) 
        return NGX_ERROR;

    ngx_log_error (NGX_LOG_NOTICE, cycle->log, 0, "HCL Domino NRPC Stream PreRead Module - Version %s loaded", NRPC_MODULE_VERSION);

    return NGX_OK;
}


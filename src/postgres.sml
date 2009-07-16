(* Copyright (c) 2008-2009, Adam Chlipala
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - The names of contributors may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

structure Postgres :> POSTGRES = struct

open Settings
open Print.PD
open Print

val ident = String.translate (fn #"'" => "PRIME"
                               | ch => str ch)

fun p_sql_type t =
    case t of
        Int => "int8"
      | Float => "float8"
      | String => "text"
      | Bool => "bool"
      | Time => "timestamp"
      | Blob => "bytea"
      | Channel => "int8"
      | Client => "int4"
      | Nullable t => p_sql_type t

fun p_sql_type_base t =
    case t of
        Int => "bigint"
      | Float => "double precision"
      | String => "text"
      | Bool => "boolean"
      | Time => "timestamp without time zone"
      | Blob => "bytea"
      | Channel => "bigint"
      | Client => "integer"
      | Nullable t => p_sql_type_base t

fun checkRel (table, checkNullable) (s, xts) =
    let
        val sl = CharVector.map Char.toLower s

        val q = "SELECT COUNT(*) FROM information_schema." ^ table ^ " WHERE table_name = '"
                ^ sl ^ "'"

        val q' = String.concat ["SELECT COUNT(*) FROM information_schema.columns WHERE table_name = '",
                                sl,
                                "' AND (",
                                String.concatWith " OR "
                                                  (map (fn (x, t) =>
                                                           String.concat ["(column_name = 'uw_",
                                                                          CharVector.map
                                                                              Char.toLower (ident x),
                                                                          "' AND data_type = '",
                                                                          p_sql_type_base t,
                                                                          "'",
                                                                          if checkNullable then
                                                                              (" AND is_nullable = '"
                                                                               ^ (if isNotNull t then
                                                                                      "NO"
                                                                                  else
                                                                                      "YES")
                                                                               ^ "'")
                                                                          else
                                                                              "",
                                                                          ")"]) xts),
                                ")"]

        val q'' = String.concat ["SELECT COUNT(*) FROM information_schema.columns WHERE table_name = '",
                                 sl,
                                 "' AND column_name LIKE 'uw_%'"]
    in
        box [string "res = PQexec(conn, \"",
             string q,
             string "\");",
             newline,
             newline,
             string "if (res == NULL) {",
             newline,
             box [string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Out of memory allocating query result.\");",
                  newline],
             string "}",
             newline,
             newline,
             string "if (PQresultStatus(res) != PGRES_TUPLES_OK) {",
             newline,
             box [string "char msg[1024];",
                  newline,
                  string "strncpy(msg, PQerrorMessage(conn), 1024);",
                  newline,
                  string "msg[1023] = 0;",
                  newline,
                  string "PQclear(res);",
                  newline,
                  string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Query failed:\\n",
                  string q,
                  string "\\n%s\", msg);",
                  newline],
             string "}",
             newline,
             newline,
             string "if (strcmp(PQgetvalue(res, 0, 0), \"1\")) {",
             newline,
             box [string "PQclear(res);",
                  newline,
                  string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Table '",
                  string s,
                  string "' does not exist.\");",
                  newline],
             string "}",
             newline,
             newline,
             string "PQclear(res);",
             newline,

             string "res = PQexec(conn, \"",
             string q',
             string "\");",
             newline,
             newline,
             string "if (res == NULL) {",
             newline,
             box [string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Out of memory allocating query result.\");",
                  newline],
             string "}",
             newline,
             newline,
             string "if (PQresultStatus(res) != PGRES_TUPLES_OK) {",
             newline,
             box [string "char msg[1024];",
                  newline,
                  string "strncpy(msg, PQerrorMessage(conn), 1024);",
                  newline,
                  string "msg[1023] = 0;",
                  newline,
                  string "PQclear(res);",
                  newline,
                  string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Query failed:\\n",
                  string q',
                  string "\\n%s\", msg);",
                  newline],
             string "}",
             newline,
             newline,
             string "if (strcmp(PQgetvalue(res, 0, 0), \"",
             string (Int.toString (length xts)),
             string "\")) {",
             newline,
             box [string "PQclear(res);",
                  newline,
                  string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Table '",
                  string s,
                  string "' has the wrong column types.\");",
                  newline],
             string "}",
             newline,
             newline,
             string "PQclear(res);",
             newline,
             newline,

             string "res = PQexec(conn, \"",
             string q'',
             string "\");",
             newline,
             newline,
             string "if (res == NULL) {",
             newline,
             box [string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Out of memory allocating query result.\");",
                  newline],
             string "}",
             newline,
             newline,
             string "if (PQresultStatus(res) != PGRES_TUPLES_OK) {",
             newline,
             box [string "char msg[1024];",
                  newline,
                  string "strncpy(msg, PQerrorMessage(conn), 1024);",
                  newline,
                  string "msg[1023] = 0;",
                  newline,
                  string "PQclear(res);",
                  newline,
                  string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Query failed:\\n",
                  string q'',
                  string "\\n%s\", msg);",
                  newline],
             string "}",
             newline,
             newline,
             string "if (strcmp(PQgetvalue(res, 0, 0), \"",
             string (Int.toString (length xts)),
             string "\")) {",
             newline,
             box [string "PQclear(res);",
                  newline,
                  string "PQfinish(conn);",
                  newline,
                  string "uw_error(ctx, FATAL, \"Table '",
                  string s,
                  string "' has extra columns.\");",
                  newline],
             string "}",
             newline,
             newline,
             string "PQclear(res);",
             newline]
    end

fun init {dbstring, prepared = ss, tables, views, sequences} =
    box [if #persistent (currentProtocol ()) then
             box [string "void uw_client_init(void) {",
                  newline,
                  box [string "uw_sqlfmtInt = \"%lld::int8%n\";",
                       newline,
                       string "uw_sqlfmtFloat = \"%g::float8%n\";",
                       newline,
                       string "uw_Estrings = 1;",
                       newline,
                       string "uw_sqlsuffixString = \"::text\";",
                       newline,
                       string "uw_sqlsuffixBlob = \"::bytea\";",
                       newline,
                       string "uw_sqlfmtUint4 = \"%u::int4%n\";",
                       newline],
                  string "}",
                  newline,
                  newline,

                  string "static void uw_db_validate(uw_context ctx) {",
                  newline,
                  string "PGconn *conn = uw_get_db(ctx);",
                  newline,
                  string "PGresult *res;",
                  newline,
                  newline,
                  p_list_sep newline (checkRel ("tables", true)) tables,
                  p_list_sep newline (checkRel ("views", false)) views,

                  p_list_sep newline
                             (fn s =>
                                 let
                                     val sl = CharVector.map Char.toLower s

                                     val q = "SELECT COUNT(*) FROM pg_class WHERE relname = '"
                                             ^ sl ^ "' AND relkind = 'S'"
                                 in
                                     box [string "res = PQexec(conn, \"",
                                          string q,
                                          string "\");",
                                          newline,
                                          newline,
                                          string "if (res == NULL) {",
                                          newline,
                                          box [string "PQfinish(conn);",
                                               newline,
                                               string "uw_error(ctx, FATAL, \"Out of memory allocating query result.\");",
                                               newline],
                                          string "}",
                                          newline,
                                          newline,
                                          string "if (PQresultStatus(res) != PGRES_TUPLES_OK) {",
                                          newline,
                                          box [string "char msg[1024];",
                                               newline,
                                               string "strncpy(msg, PQerrorMessage(conn), 1024);",
                                               newline,
                                               string "msg[1023] = 0;",
                                               newline,
                                               string "PQclear(res);",
                                               newline,
                                               string "PQfinish(conn);",
                                               newline,
                                               string "uw_error(ctx, FATAL, \"Query failed:\\n",
                                               string q,
                                               string "\\n%s\", msg);",
                                               newline],
                                          string "}",
                                          newline,
                                          newline,
                                          string "if (strcmp(PQgetvalue(res, 0, 0), \"1\")) {",
                                          newline,
                                          box [string "PQclear(res);",
                                               newline,
                                               string "PQfinish(conn);",
                                               newline,
                                               string "uw_error(ctx, FATAL, \"Sequence '",
                                               string s,
                                               string "' does not exist.\");",
                                               newline],
                                          string "}",
                                          newline,
                                          newline,
                                          string "PQclear(res);",
                                          newline]
                                 end) sequences,

                  string "}",

                  string "static void uw_db_prepare(uw_context ctx) {",
                  newline,
                  string "PGconn *conn = uw_get_db(ctx);",
                  newline,
                  string "PGresult *res;",
                  newline,
                  newline,

                  p_list_sepi newline (fn i => fn (s, n) =>
                                                  box [string "res = PQprepare(conn, \"uw",
                                                       string (Int.toString i),
                                                       string "\", \"",
                                                       string (String.toString s),
                                                       string "\", ",
                                                       string (Int.toString n),
                                                       string ", NULL);",
                                                       newline,
                                                       string "if (PQresultStatus(res) != PGRES_COMMAND_OK) {",
                                                       newline,
                                                       box [string "char msg[1024];",
                                                            newline,
                                                            string "strncpy(msg, PQerrorMessage(conn), 1024);",
                                                            newline,
                                                            string "msg[1023] = 0;",
                                                            newline,
                                                            string "PQclear(res);",
                                                            newline,
                                                            string "PQfinish(conn);",
                                                            newline,
                                                            string "uw_error(ctx, FATAL, \"Unable to create prepared statement:\\n",
                                                            string (String.toString s),
                                                            string "\\n%s\", msg);",
                                                            newline],
                                                       string "}",
                                                       newline,
                                                       string "PQclear(res);",
                                                       newline])
                              ss,

                  string "}",
                  newline,
                  newline,

                  string "void uw_db_close(uw_context ctx) {",
                  newline,
                  string "PQfinish(uw_get_db(ctx));",
                  newline,
                  string "}",
                  newline,
                  newline,

                  string "int uw_db_begin(uw_context ctx) {",
                  newline,
                  string "PGconn *conn = uw_get_db(ctx);",
                  newline,
                  string "PGresult *res = PQexec(conn, \"BEGIN ISOLATION LEVEL SERIALIZABLE\");",
                  newline,
                  newline,
                  string "if (res == NULL) return 1;",
                  newline,
                  newline,
                  string "if (PQresultStatus(res) != PGRES_COMMAND_OK) {",
                  box [string "PQclear(res);",
                       newline,
                       string "return 1;",
                       newline],
                  string "}",
                  newline,
                  string "return 0;",
                  newline,
                  string "}",
                  newline,
                  newline,

                  string "int uw_db_commit(uw_context ctx) {",
                  newline,
                  string "PGconn *conn = uw_get_db(ctx);",
                  newline,
                  string "PGresult *res = PQexec(conn, \"COMMIT\");",
                  newline,
                  newline,
                  string "if (res == NULL) return 1;",
                  newline,
                  newline,
                  string "if (PQresultStatus(res) != PGRES_COMMAND_OK) {",
                  box [string "PQclear(res);",
                       newline,
                       string "return 1;",
                       newline],
                  string "}",
                  newline,
                  string "return 0;",
                  newline,
                  string "}",
                  newline,
                  newline,

                  string "int uw_db_rollback(uw_context ctx) {",
                  newline,
                  string "PGconn *conn = uw_get_db(ctx);",
                  newline,
                  string "PGresult *res = PQexec(conn, \"ROLLBACK\");",
                  newline,
                  newline,
                  string "if (res == NULL) return 1;",
                  newline,
                  newline,
                  string "if (PQresultStatus(res) != PGRES_COMMAND_OK) {",
                  box [string "PQclear(res);",
                       newline,
                       string "return 1;",
                       newline],
                  string "}",
                  newline,
                  string "return 0;",
                  newline,
                  string "}",
                  newline,
                  newline]
         else
             box [string "static void uw_db_validate(uw_context ctx) { }",
                  newline,
                  string "static void uw_db_prepare(uw_context ctx) { }"],

         newline,
         newline,

         string "void uw_db_init(uw_context ctx) {",
         newline,
         string "PGconn *conn = PQconnectdb(\"",
         string (String.toString dbstring),
         string "\");",
         newline,
         string "if (conn == NULL) uw_error(ctx, FATAL, ",
         string "\"libpq can't allocate a connection.\");",
         newline,
         string "if (PQstatus(conn) != CONNECTION_OK) {",
         newline,
         box [string "char msg[1024];",
              newline,
              string "strncpy(msg, PQerrorMessage(conn), 1024);",
              newline,
              string "msg[1023] = 0;",
              newline,
              string "PQfinish(conn);",
              newline,
              string "uw_error(ctx, BOUNDED_RETRY, ",
              string "\"Connection to Postgres server failed: %s\", msg);"],
         newline,
         string "}",
         newline,
         string "uw_set_db(ctx, conn);",
         newline,
         string "uw_db_validate(ctx);",
         newline,
         string "uw_db_prepare(ctx);",
         newline,
         string "}"]

fun p_getcol {wontLeakStrings, col = i, typ = t} =
    let
        fun p_unsql t e eLen =
            case t of
                Int => box [string "uw_Basis_stringToInt_error(ctx, ", e, string ")"]
              | Float => box [string "uw_Basis_stringToFloat_error(ctx, ", e, string ")"]
              | String =>
                if wontLeakStrings then
                    e
                else
                    box [string "uw_strdup(ctx, ", e, string ")"]
              | Bool => box [string "uw_Basis_stringToBool_error(ctx, ", e, string ")"]
              | Time => box [string "uw_Basis_stringToTime_error(ctx, ", e, string ")"]
              | Blob => box [string "uw_Basis_stringToBlob_error(ctx, ",
                             e,
                             string ", ",
                             eLen,
                             string ")"]
              | Channel => box [string "uw_Basis_stringToChannel_error(ctx, ", e, string ")"]
              | Client => box [string "uw_Basis_stringToClient_error(ctx, ", e, string ")"]

              | Nullable _ => raise Fail "Postgres: Recursive Nullable"

        fun getter t =
            case t of
                Nullable t =>
                box [string "(PQgetisnull(res, i, ",
                     string (Int.toString i),
                     string ") ? NULL : ",
                     case t of
                         String => getter t
                       | _ => box [string "({",
                                   newline,
                                   string (p_sql_ctype t),
                                   space,
                                   string "*tmp = uw_malloc(ctx, sizeof(",
                                   string (p_sql_ctype t),
                                   string "));",
                                   newline,
                                   string "*tmp = ",
                                   getter t,
                                   string ";",
                                   newline,
                                   string "tmp;",
                                   newline,
                                   string "})"],
                     string ")"]
              | _ =>
                box [string "(PQgetisnull(res, i, ",
                     string (Int.toString i),
                     string ") ? ",
                     box [string "({",
                          string (p_sql_ctype t),
                          space,
                          string "tmp;",
                          newline,
                          string "uw_error(ctx, FATAL, \"Unexpectedly NULL field #",
                          string (Int.toString i),
                          string "\");",
                          newline,
                          string "tmp;",
                          newline,
                          string "})"],
                     string " : ",
                     p_unsql t
                             (box [string "PQgetvalue(res, i, ",
                                   string (Int.toString i),
                                   string ")"])
                             (box [string "PQgetlength(res, i, ",
                                   string (Int.toString i),
                                   string ")"]),
                     string ")"]
    in
        getter t
    end

fun queryCommon {loc, query, cols, doCols} =
    box [string "int n, i;",
         newline,
         newline,

         string "if (res == NULL) uw_error(ctx, FATAL, \"Out of memory allocating query result.\");",
         newline,
         newline,

         string "if (PQresultStatus(res) != PGRES_TUPLES_OK) {",
         newline,
         box [string "PQclear(res);",
              newline,
              string "uw_error(ctx, FATAL, \"",
              string (ErrorMsg.spanToString loc),
              string ": Query failed:\\n%s\\n%s\", ",
              query,
              string ", PQerrorMessage(conn));",
              newline],
         string "}",
         newline,
         newline,

         string "if (PQnfields(res) != ",
         string (Int.toString (length cols)),
         string ") {",
         newline,
         box [string "int nf = PQnfields(res);",
              newline,
              string "PQclear(res);",
              newline,
              string "uw_error(ctx, FATAL, \"",
              string (ErrorMsg.spanToString loc),
              string ": Query returned %d columns instead of ",
              string (Int.toString (length cols)),
              string ":\\n%s\\n%s\", nf, ",
              query,
              string ", PQerrorMessage(conn));",
              newline],
         string "}",
         newline,
         newline,

         string "uw_end_region(ctx);",
         newline,
         string "uw_push_cleanup(ctx, (void (*)(void *))PQclear, res);",
         newline,
         string "n = PQntuples(res);",
         newline,
         string "for (i = 0; i < n; ++i) {",
         newline,
         doCols p_getcol,
         string "}",
         newline,
         newline,
         string "uw_pop_cleanup(ctx);",
         newline]    

fun query {loc, cols, doCols} =
    box [string "PGconn *conn = uw_get_db(ctx);",
         newline,
         string "PGresult *res = PQexecParams(conn, query, 0, NULL, NULL, NULL, NULL, 0);",
         newline,
         newline,
         queryCommon {loc = loc, cols = cols, doCols = doCols, query = string "query"}]

fun p_ensql t e =
    case t of
        Int => box [string "uw_Basis_attrifyInt(ctx, ", e, string ")"]
      | Float => box [string "uw_Basis_attrifyFloat(ctx, ", e, string ")"]
      | String => e
      | Bool => box [string "(", e, string " ? \"TRUE\" : \"FALSE\")"]
      | Time => box [string "uw_Basis_attrifyTime(ctx, ", e, string ")"]
      | Blob => box [e, string ".data"]
      | Channel => box [string "uw_Basis_attrifyChannel(ctx, ", e, string ")"]
      | Client => box [string "uw_Basis_attrifyClient(ctx, ", e, string ")"]
      | Nullable String => e
      | Nullable t => box [string "(",
                           e,
                           string " == NULL ? NULL : ",
                           p_ensql t (box [string "(*", e, string ")"]),
                           string ")"]

fun queryPrepared {loc, id, query, inputs, cols, doCols, nested = _} =
    box [string "PGconn *conn = uw_get_db(ctx);",
         newline,
         string "const int paramFormats[] = { ",
         p_list_sep (box [string ",", space])
                    (fn t => if isBlob t then string "1" else string "0") inputs,
         string " };",
         newline,
         string "const int paramLengths[] = { ",
         p_list_sepi (box [string ",", space])
                     (fn i => fn Blob => string ("arg" ^ Int.toString (i + 1) ^ ".size")
                               | Nullable Blob => string ("arg" ^ Int.toString (i + 1)
                                                          ^ "?arg" ^ Int.toString (i + 1) ^ "->size:0")
                               | _ => string "0") inputs,
         string " };",
         newline,
         string "const char *paramValues[] = { ",
         p_list_sepi (box [string ",", space])
                     (fn i => fn t => p_ensql t (box [string "arg",
                                                      string (Int.toString (i + 1))]))
                     inputs,
         string " };",
         newline,
         newline,
         string "PGresult *res = ",
         if #persistent (Settings.currentProtocol ()) then
             box [string "PQexecPrepared(conn, \"uw",
                  string (Int.toString id),
                  string "\", ",
                  string (Int.toString (length inputs)),
                  string ", paramValues, paramLengths, paramFormats, 0);"]
         else
             box [string "PQexecParams(conn, \"",
                  string (String.toString query),
                  string "\", ",
                  string (Int.toString (length inputs)),
                  string ", NULL, paramValues, paramLengths, paramFormats, 0);"],
         newline,
         newline,
         queryCommon {loc = loc, cols = cols, doCols = doCols, query = box [string "\"",
                                                                            string (String.toString query),
                                                                            string "\""]}]

fun dmlCommon {loc, dml} =
    box [string "if (res == NULL) uw_error(ctx, FATAL, \"Out of memory allocating DML result.\");",
         newline,
         newline,

         string "if (PQresultStatus(res) != PGRES_COMMAND_OK) {",
         newline,
         box [string "if (!strcmp(PQresultErrorField(res, PG_DIAG_SQLSTATE), \"40001\")) {",
              box [newline,
                   string "PQclear(res);",
                   newline,
                   string "uw_error(ctx, UNLIMITED_RETRY, \"Serialization failure\");",
                   newline],
              string "}",
              newline,
              string "PQclear(res);",
              newline,
              string "uw_error(ctx, FATAL, \"",
              string (ErrorMsg.spanToString loc),
              string ": DML failed:\\n%s\\n%s\", ",
              dml,
              string ", PQerrorMessage(conn));",
              newline],
         string "}",
         newline,
         newline,

         string "PQclear(res);",
         newline]

fun dml loc =
    box [string "PGconn *conn = uw_get_db(ctx);",
         newline,
         string "PGresult *res = PQexecParams(conn, dml, 0, NULL, NULL, NULL, NULL, 0);",
         newline,
         newline,
         dmlCommon {loc = loc, dml = string "dml"}]

fun dmlPrepared {loc, id, dml, inputs} =
    box [string "PGconn *conn = uw_get_db(ctx);",
         newline,
         string "const int paramFormats[] = { ",
         p_list_sep (box [string ",", space])
                    (fn t => if isBlob t then string "1" else string "0") inputs,
         string " };",
         newline,
         string "const int paramLengths[] = { ",
         p_list_sepi (box [string ",", space])
                     (fn i => fn Blob => string ("arg" ^ Int.toString (i + 1) ^ ".size")
                               | Nullable Blob => string ("arg" ^ Int.toString (i + 1)
                                                          ^ "?arg" ^ Int.toString (i + 1) ^ "->size:0")
                               | _ => string "0") inputs,
         string " };",
         newline,
         string "const char *paramValues[] = { ",
         p_list_sepi (box [string ",", space])
                     (fn i => fn t => p_ensql t (box [string "arg",
                                                      string (Int.toString (i + 1))]))
                     inputs,
         string " };",
         newline,
         newline,
         string "PGresult *res = ",
         if #persistent (Settings.currentProtocol ()) then
             box [string "PQexecPrepared(conn, \"uw",
                  string (Int.toString id),
                  string "\", ",
                  string (Int.toString (length inputs)),
                  string ", paramValues, paramLengths, paramFormats, 0);"]
         else
             box [string "PQexecParams(conn, \"",
                  string (String.toString dml),
                  string "\", ",
                  string (Int.toString (length inputs)),
                  string ", NULL, paramValues, paramLengths, paramFormats, 0);"],
         newline,
         newline,
         dmlCommon {loc = loc, dml = box [string "\"",
                                          string (String.toString dml),
                                          string "\""]}]

fun nextvalCommon {loc, query} =
    box [string "if (res == NULL) uw_error(ctx, FATAL, \"Out of memory allocating nextval result.\");",
         newline,
         newline,

         string "if (PQresultStatus(res) != PGRES_TUPLES_OK) {",
         newline,
         box [string "PQclear(res);",
              newline,
              string "uw_error(ctx, FATAL, \"",
              string (ErrorMsg.spanToString loc),
              string ": Query failed:\\n%s\\n%s\", ",
              query,
              string ", PQerrorMessage(conn));",
              newline],
         string "}",
         newline,
         newline,

         string "n = PQntuples(res);",
         newline,
         string "if (n != 1) {",
         newline,
         box [string "PQclear(res);",
              newline,
              string "uw_error(ctx, FATAL, \"",
              string (ErrorMsg.spanToString loc),
              string ": Wrong number of result rows:\\n%s\\n%s\", ",
              query,
              string ", PQerrorMessage(conn));",
              newline],
         string "}",
         newline,
         newline,

         string "n = uw_Basis_stringToInt_error(ctx, PQgetvalue(res, 0, 0));",
         newline,
         string "PQclear(res);",
         newline]

open Cjr

fun nextval {loc, seqE, seqName} =
    let
        val query = case seqName of
                        SOME s =>
                        string ("\"SELECT NEXTVAL('" ^ s ^ "')\"")
                      | _ => box [string "uw_Basis_strcat(ctx, \"SELECT NEXTVAL('\", uw_Basis_strcat(ctx, ",
                                  seqE,
                                  string ", \"')\"))"]
    in
        box [string "char *query = ",
             query,
             string ";",
             newline,
             string "PGconn *conn = uw_get_db(ctx);",
             newline,
             string "PGresult *res = PQexecParams(conn, query, 0, NULL, NULL, NULL, NULL, 0);",
             newline,
             newline,
             nextvalCommon {loc = loc, query = string "query"}]
    end

fun nextvalPrepared {loc, id, query} =
    box [string "PGconn *conn = uw_get_db(ctx);",
         newline,
         newline,
         string "PGresult *res = ",
         if #persistent (Settings.currentProtocol ()) then
             box [string "PQexecPrepared(conn, \"uw",
                  string (Int.toString id),
                  string "\", 0, NULL, NULL, NULL, 0);"]
         else
             box [string "PQexecParams(conn, \"",
                  string (String.toString query),
                  string "\", 0, NULL, NULL, NULL, NULL, 0);"],
         newline,
         newline,
         nextvalCommon {loc = loc, query = box [string "\"",
                                                string (String.toString query),
                                                string "\""]}]

fun sqlifyString s = "E'" ^ String.translate (fn #"'" => "\\'"
                                               | #"\\" => "\\\\"
                                               | ch =>
                                                 if Char.isPrint ch then
                                                     str ch
                                                 else
                                                     "\\" ^ StringCvt.padLeft #"0" 3
                                                                              (Int.fmt StringCvt.OCT (ord ch)))
                                             (String.toString s) ^ "'::text"

fun p_cast (s, t) = s ^ "::" ^ p_sql_type t

fun p_blank (n, t) = p_cast ("$" ^ Int.toString n, t)

val () = addDbms {name = "postgres",
                  header = "postgresql/libpq-fe.h",
                  link = "-lpq",
                  p_sql_type = p_sql_type,
                  init = init,
                  query = query,
                  queryPrepared = queryPrepared,
                  dml = dml,
                  dmlPrepared = dmlPrepared,
                  nextval = nextval,
                  nextvalPrepared = nextvalPrepared,
                  sqlifyString = sqlifyString,
                  p_cast = p_cast,
                  p_blank = p_blank,
                  supportsDeleteAs = true,
                  createSequence = fn s => "CREATE SEQUENCE " ^ s,
                  textKeysNeedLengths = false,
                  supportsNextval = true,
                  supportsNestedPrepared = true}

val () = setDbms "postgres"

end
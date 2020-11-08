# quick-plsql
Code generator for Oracle PL/SQL based on a simple markup language

For more information, see https://ora-00001.blogspot.com/2018/08/quick-plsql-code-generator-for-plsql.html

## Prerequisites

sql_util_pkg and string_util_pkg from the Alexandria PL/SQL Utility Library (https://github.com/mortenbra/alexandria-plsql-utils)

Minimum APEX version: 20.2

## Installation

* Install the prerequisite packages (see above)
* Install the main package specification (codegen_quickplsql_pkg.pks) and package body (codegen_quickplsql_pkg.pkb)
* Install application (f133.sql) into your APEX workspace
